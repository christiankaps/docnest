# Label Units, Document Values, and Filter Statistics Plan

## Goal

Extend labels with an optional unit, such as `Invoice` with unit `€`, and allow each document carrying that label to optionally store one numeric value for that label. When the document list is filtered to a single value-enabled label, show basic statistics for the filtered documents that have a value for that label: sum, average, minimum, maximum, and median.

Example: if `Invoice` has unit `€`, documents labeled `Invoice` can store invoice amounts. Filtering by `Invoice` shows statistics over the visible invoice values.

## Current Code Shape

- `LabelTag` is the persisted label model in `DocNest/Domain/Entities/LabelTag.swift`.
- `DocumentRecord` stores labels through a SwiftData many-to-many relationship in `DocNest/Domain/Entities/DocumentRecord.swift`.
- Label creation, rename, delete, assignment, and removal live in `ManageLabelsUseCase`.
- `LibraryCoordinator` derives active, trashed, filtered, and selected document sets, and does expensive filter work off the main actor using `SearchDocumentsUseCase.Snapshot`.
- The document inspector owns single-document label assignment UI and multi-selection label operations.
- The bottom of the left sidebar is the preferred place to show aggregate value information because it has enough room to show filtered and selected scopes together.
- SwiftData schema evolution is managed in `DocNestSchemaVersioning.swift`; the current schema is V4.

## Product Decisions

- A label has zero or one unit. The unit is metadata on `LabelTag`, not on each document.
- A document-label assignment has zero or one numeric value. This value is metadata for the specific document and label pair.
- Exactly one value per document-label pair is the lasting constraint for this feature; do not design for multiple values per pair.
- Statistics only appear when the effective label filter context resolves to exactly one label with a non-empty unit. Additional non-unit labels may still narrow the filtered documents. If a document has several value-enabled labels, the statistics still describe only the single active value label; values from different labels or units are never combined.
- Statistics show the active value label name and unit, then the relevant document scopes:
  - `Filtered` uses the currently filtered document set and is always shown
  - `Selection` uses selected documents that are still visible in the current filtered set and is shown only when more than one visible document is selected
- Statistics ignore empty/missing values for numeric calculations, including average and median.
- The statistic surface must show both the number of documents with a value and the total document count in the current scope, so missing values are visible instead of silent.
- Smart folder selections should show statistics when the effective smart-folder label set contains exactly one value-enabled label. Non-unit labels in the same smart folder, such as `Invoice + 2026`, still scope the visible documents but do not make the statistic ambiguous.
- Values are entered manually inline from the document list label chip. Automatic OCR extraction of values is out of scope for this feature.
- Values are plain numeric quantities formatted with the label's free-form unit string. True currency handling with ISO codes is out of scope for v1.
- Statistics are on-screen only for v1; copy/export of statistics is out of scope.

## Data Model Plan

Add `unitSymbol: String?` to `LabelTag`.

Add a new persisted model, tentatively named `DocumentLabelValue`, representing optional value metadata for one document-label pair:

- `id: UUID`
- `documentID: UUID`
- `labelID: UUID`
- `decimalString: String`
- `updatedAt: Date`

Use `Decimal` in domain/UI calculations, but persist a normalized decimal string instead of `Double` to avoid currency rounding surprises. The value model intentionally keys by stable `UUID`s rather than SwiftData object references, because the existing many-to-many label relationship remains the source of truth for assignment membership.

Treat `DocumentRecord.id` and `LabelTag.id` as immutable identity fields. No migration, import repair, integrity repair, merge, or rename flow may regenerate those UUIDs for existing records, because `DocumentLabelValue` rows depend on them.

Keep the existing `DocumentRecord.labels` and `LabelTag.documents` many-to-many relationship unchanged for filtering, search, smart folders, export naming, and existing UI flows. The value table is supplemental and should never be used to determine whether a label is assigned.

Enforce exactly one live value row per `(documentID, labelID)` pair. Prefer a SwiftData uniqueness constraint if available and reliable for this schema shape. If not, centralize all writes through a single fetch-then-update use case that:

- fetches all rows for the pair before writing
- updates the first row
- deletes duplicate rows for the same pair
- saves only after duplicates have been collapsed

No view should create or mutate `DocumentLabelValue` directly.

Add helper APIs around value lookup and mutation rather than reading raw value rows from views:

- fetch or create value for a document-label pair
- set value
- clear value
- remove stale values when a label is removed from documents
- remove values when a label is deleted
- remove values when documents are permanently deleted by `DeleteDocumentsUseCase.execute`
- repair/prune values for document-label pairs that no longer exist
- deduplicate repeated `(documentID, labelID)` rows during repair/prune
- repair/prune values whose document or label was removed outside the supported use cases

## Migration Plan

Create schema V5 in `DocNestSchemaVersioning.swift`:

- V5 includes `DocumentRecord`, `LabelTag`, `SmartFolder`, `LabelGroup`, `WatchFolder`, and `DocumentLabelValue`.
- `LabelTag` gains nullable `unitSymbol`.
- Add `MigrationStage.lightweight(fromVersion: DocNestSchemaV4.self, toVersion: DocNestSchemaV5.self)` if SwiftData accepts the nullable field and new model as lightweight changes.
- If lightweight migration fails in testing, switch to a custom V4-to-V5 stage that opens old labels/documents unchanged and initializes no value rows.

Update `DocumentLibraryService.openModelContainer` only if its schema model list or diagnostics need explicit references to the new model. Also update integrity reporting to identify orphaned value rows if the repair path is added there.

Regression risk: the current V4 schema references top-level model types directly. V5 should either continue that pattern carefully or snapshot nested V5 model types if the project wants future checksums to be more stable. The implementation should verify opening an existing V4 library with labels still preserves assignments and creates no spurious values.

## Domain Logic Plan

Add a use case, tentatively `ManageLabelValuesUseCase`, with focused responsibilities:

- normalize unit text using collapsed whitespace and a length limit
- normalize numeric input into a locale-independent decimal string
- parse persisted decimal strings into `Decimal`
- set and clear a document value for a label
- compute statistics for documents filtered by a target label
- prune stale value rows
- delete all values for a set of document IDs before `DeleteDocumentsUseCase.execute` hard-deletes documents
- increment or publish a lightweight value metadata revision after any unit or value mutation so coordinator-derived statistics can refresh

Update `ManageLabelsUseCase`:

- `createLabel` accepts optional `unitSymbol`
- `update` accepts optional `unitSymbol`
- same-name create keeps current dedupe behavior and returns the existing label without changing its unit; the full edit surfaces are responsible for intentional unit changes
- same-name create from a full create/edit surface must give user-visible feedback when the existing label's unit differs from the requested unit, instead of silently appearing to create `Invoice (€)` while reusing a unitless `Invoice`
- clearing a label's unit must be a single transactional use-case operation:
  - count affected documents with stored values
  - warn the user and show that affected document count
  - after confirmation, delete the value rows and clear `unitSymbol`
  - save once after both mutations are staged
  - leave both unit and values unchanged if validation or save fails
- deleting a label deletes or prunes its `DocumentLabelValue` rows
- removing a label from documents clears values for those document-label pairs
- merging labels during rename/update must merge value rows carefully:
  - if the destination label has no value for a document, move the old value to the destination label
  - if both source and destination already have values for the same document, preserve the destination value and discard the source value

Ban direct `modelContext.delete(label)` calls for `LabelTag` outside `ManageLabelsUseCase`. Existing tests or future helpers that delete labels directly must be updated to use the use case or must be explicitly testing repair of unsupported direct deletion. This prevents value rows from bypassing cleanup.

Update `DeleteDocumentsUseCase`:

- before deleting `DocumentRecord` instances from the model context, clear all `DocumentLabelValue` rows whose `documentID` is in the target document set
- cover both `removeFromLibrary` and `deleteStoredFiles`; moving to Bin and restoring from Bin should keep values

Add a value statistics type, tentatively `LabelValueStatistics`:

- `labelID`
- `unitSymbol`
- `scope`
- `availableScopes`
- `scopeDocumentCount`
- `valuedDocumentCount`
- `missingValueCount`
- `sum`
- `average`
- `minimum`
- `maximum`
- `median`

Median behavior:

- sort parsed `Decimal` values ascending
- odd count: middle value
- even count: average of the two middle values
- no values: statistics still produce an empty state for a filter context with exactly one value-enabled label, so the UI can show `0 of N valued` instead of hiding the feature entirely

Calculation behavior:

- `sum`, `average`, `minimum`, `maximum`, and `median` use only documents in scope that have a valid stored value for the target label
- empty/missing values are counted in `missingValueCount` but are not treated as zero
- average divides by `valuedDocumentCount`, not `scopeDocumentCount`
- guard `valuedDocumentCount > 0` before computing average or median so division by zero is impossible
- when `valuedDocumentCount == 0`, numeric statistic fields should be absent, disabled, or shown as `-`

## Coordinator Plan

Extend `LibraryCoordinator` with derived state for the currently relevant statistics:

- `private(set) var activeLabelValueStatistics: LabelValueStatistics?`

Recompute this after filtered documents are updated. The statistic computation can be synchronous for small data, but should be placed behind the same generation guard or a separate cancellable task if value counts may grow large.

Document selection must never wait for statistics calculation. Treat statistics as derived, lower-priority UI state:

- selection updates, inspector updates, and row highlighting happen immediately
- statistics recomputation runs after selection/filter state has been applied
- large or potentially expensive calculations run in a cancellable background `Task`
- stale statistics tasks are cancelled when selection, filter, search, label metadata, or value rows change
- generation checks prevent old results from overwriting newer UI state
- while recalculating, keep the last valid statistic briefly or show a small non-blocking updating indicator; do not freeze or defer selection feedback

Do not rely only on `filteredDocuments` changes for invalidation. Statistics also depend on label unit metadata and value rows, so recomputation must be triggered when:

- the filtered document set changes
- the current visible selection changes
- the effective label filter changes
- a label unit is created, edited, cleared, or merged
- a value is set, updated, cleared, pruned, deduplicated, or deleted
No user-facing scope toggle is needed; the sidebar footer derives scope visibility from the current filter and selection.

Implementation options:

- maintain a `labelValueRevision` integer on `LibraryCoordinator` and bump it after value/unit mutations
- include fetched `DocumentLabelValue` rows in coordinator ingestion and derive a stable signature from relevant rows
- use `@Query` in the root view for `DocumentLabelValue` and pass rows into `LibraryCoordinator.ingest`

Whichever option is chosen, inline list value edits must update the visible statistics without requiring the user to change filters.

Use the effective filter context:

- normal sidebar section: `labelFilterSelection.appliedSelection`
- smart folder: selected smart folder label IDs
- current sidebar section, including Recent, Bin, and Needs Labels
- current search text

Statistics appear only when the effective label set resolves to exactly one label with a unit. Non-unit labels can still narrow the documents. This keeps behavior predictable for AND filters like `Invoice + 2026`, while suppressing stats for `Invoice (€) + Hours (h)` because two value-enabled labels would be ambiguous.

The coordinator should not include trashed documents unless the current filtered document set is the Bin view. It should simply use `filteredDocuments`, after section filtering and search have already been applied, so the statistic always describes exactly what the user is looking at.

Statistics scopes:

- always compute and show `Filtered`, even when the document list has an automatic or explicit single-document selection
- compute `Selection` for selected documents still present in `filteredDocuments`, but show it only when more than one visible document is selected
- hide single-document and empty selection statistics rather than falling back to filtered statistics
- expose the scope in each `LabelValueStatistics.scope`, for example `.selection` or `.filtered`, so the UI can label each block
- if selection changes, selection statistics must refresh without blocking row highlighting
- if selection changes, keep the filtered aggregate stable while showing, updating, or hiding the `Selection` block
- selection handling must update visible selection state before scheduling statistics recomputation, so rapid arrow-key or mouse selection remains responsive

## UI Plan

### Label Management

Add a unit field anywhere labels are created or edited:

- `LabelManagerSheet`
- `LabelEditorSheet`, if still reachable
- sidebar quick-create flow, if it has label creation controls
- `WatchFolderEditorSheet` create-new-label flow
- inspector single-document `Create and assign label` flow
- inspector multi-selection `Create and assign label to selection` flow

For compact create-and-assign flows, do not add a unit field unless there is enough room and the workflow remains clear. It is acceptable for quick-create flows to create labels without units and rely on the full label editor for adding the unit later. The important requirement is that this behavior is intentional and documented in code/UI tests.

Use a compact text field labeled `Unit` with placeholder examples such as `€`, `USD`, `kg`, or `h`. Empty means no value support for that label. Keep units short enough for list rows and the statistics footer:

- normalize collapsed whitespace
- reject or require shortening units beyond 12 visible characters
- show a live preview such as `Invoice (€)` in full label editing surfaces
- explain that the unit is the value suffix shown in document values and statistics

Quick-create flows that omit the unit field must make unit editing discoverable after creation:

- newly created label rows with no unit can offer a `Set Unit...` or `Manage Label...` action
- value-enabled filter empty states can link to the label editor when the label has no unit
- context menus for label chips/rows should include `Manage Label...` where practical

When showing labels in edit/details surfaces, display the unit next to the label name only where it helps disambiguate, such as `Invoice (€)`.

### Document Inspector

Document-label value editing belongs in the document list label chip. The inspector should stay focused on label assignment and removal so there is one clear value-editing location.

For single-document inspection:

- The inspector Labels section keeps assignment and removal controls only. Value-enabled labels may show the unit as subtle secondary text, but numeric value editing happens inline from the document list label chip.
- Labels without units keep the current simple chip row.
- The inline list value field accepts localized decimal input but stores normalized decimal text.
- Clearing the inline field removes the value row.
- Invalid numeric input should not save and should show compact inline validation styling.
- Removing a label from the inspector must immediately clear the corresponding value row.
- Empty value affordances should use quiet text such as `+ value`, not `0`, so missing values are visually distinct from actual zero.
- Save behavior should be predictable:
  - commit on submit
  - commit on focus loss only when the value parses unambiguously
  - show a brief saved/normalized value confirmation after commit
  - support Escape to revert the current edit before commit
  - keep focus and show inline error when invalid
  - avoid modal alerts for normal validation mistakes

For multi-selection inspection:

- Do not add bulk value editing in the first pass unless the UX is clearly requested later.
- The multi-selection surface may show value-enabled shared labels as read-only summary rows, for example `Invoice (€): 6 of 8 valued`, but should avoid destructive bulk overwrite behavior.

### Document List Values

The document list should not permanently inflate every label pill with values. In normal browsing, label chips remain compact identity markers.

When the current filter context resolves to exactly one value-enabled label, document rows may show that label's value as a contextual read-only value indicator:

- list mode: show a stable optional `Value` column that is available in the column visibility menu, excluded from saved per-label context, and populated only for the active value-enabled label context
- if the `Value` column is hidden and a value-enabled filter is active, keep statistics visible in the sidebar footer; the column visibility menu remains the place to reveal the column
- thumbnail mode: show a small value badge below the title or near the mini label bar, only for the active value-enabled label
- missing values display as `-` or `No value` in subdued text
- zero displays as a real formatted value, never as missing
- label chips for unit-enabled labels support inline value editing in the list
- when no value-enabled label filter is active, omit the per-document value indicator entirely
- missing-value label chips reveal a `+ value` affordance on hover or row selection

### Filter Statistics

Show statistics in a footer at the bottom of the left sidebar:

- visible only when `coordinator.activeLabelValueStatistics != nil`
- the document-list status bar keeps the existing document count and selected count
- the sidebar footer shows value statistics when the current filter context has exactly one value-enabled label
- names the active value label and unit in the footer header
- shows `Filtered` without a scope picker and adds `Selection` only for multi-selection
- each scope shows `Sum`, `Avg`, `Min`, `Max`, and `Median`
- shows `valuedDocumentCount` and missing count in subdued text for each scope, for example `Selection: 3 of 5 valued` and `Filtered: 8 of 10 valued`
- formats values with the label unit
- remains visible for a filter context with exactly one value-enabled label even when no documents in either scope have values, showing `0 of N valued` and `-` for unavailable numeric fields
- handles narrow widths responsively by arranging metrics in a compact grid and scaling long numeric text rather than truncating five stats into unreadable text

Keep the footer dense and native, since this is an operational document list, not a dashboard. It should not visually compete with the document list.

Bulk and missing-value usability:

- from a multi-selection summary such as `Invoice (€): 6 of 8 valued`, a later enhancement may provide a `Show Missing` affordance that filters or steps focus through the selected visible documents missing that value without changing stored metadata
- in filtered scope, any future `Show Missing` behavior should temporarily highlight or navigate to visible documents missing the active value rather than creating a new persistent filter
- avoid a separate right-side statistics panel; use the sidebar footer, inspector focus, and existing list affordances

## Formatting Plan

Add a small formatter utility for label values:

- parse localized user input with `NumberFormatter` and fall back to a strict decimal parser
- persist decimal strings with `.` as separator and no grouping
- display with the current locale and a sensible maximum fraction digit count
- append or otherwise pair the formatted number with the label's free-form unit string consistently; do not add special currency semantics for v1

Corner cases:

- negative values should be accepted unless product requirements later forbid them
- zero is a valid value
- very large values should be bounded and rejected gracefully before they can cause slow parsing, persistence bloat, or broken layout
- define maximum input length and maximum fractional digits before implementation; a conservative starting point is 30 total digits and 6 fractional digits unless a test proves a broader range is needed
- reject exponent notation, `NaN`, `infinity`, and any non-finite or non-decimal spellings
- invalid strings, grouping separators, and comma decimal input should be tested
- empty string means clear value, not zero

## Testing Plan

Add focused tests in `DocNestTests`:

- label unit creation and update persist correctly
- same-name label creation with a requested unit reuses the existing label without silently changing its unit
- labels without units do not trigger statistics
- clearing a label unit warns with the affected document count and deletes existing values after confirmation
- clearing a label unit is atomic: a simulated save failure leaves both the unit and values unchanged
- setting, updating, and clearing a document-label value works
- repeated set operations keep one value row per document-label pair
- repair/prune deduplicates duplicate value rows
- removing a label from a document removes the corresponding value
- deleting a label removes or prunes all corresponding values
- direct/unsupported label deletion is either prevented in tests or covered by repair pruning of orphan value rows
- permanently deleting a document removes corresponding values
- moving a document to Bin preserves values, and Bin filtering uses only visible trashed documents for stats
- label merge preserves destination values and moves non-conflicting source values
- document and label UUIDs remain stable through migration and repair
- statistics compute sum, average, min, max, and median for odd and even counts
- statistics calculation does not block selection changes, row highlighting, or inspector selection updates
- stale background statistics calculations are cancelled and cannot overwrite newer statistics
- rapid selection changes in `Selection` scope remain responsive and eventually show statistics for the final selection
- statistics ignore missing values and expose missing count
- average divides by valued document count and does not treat missing values as zero
- zero-valued-document statistics do not compute average or median and cannot divide by zero
- statistics with zero valued documents show the empty statistics state rather than disappearing for a value-enabled filter
- statistics use only currently filtered documents
- statistics honor current section and search text as well as labels
- statistics show filtered scope even when a document is selected
- statistics also show selection scope when more than one visible document is selected
- selection scope is hidden for empty or single-document selections
- selection changes refresh the sidebar footer without requiring a scope toggle
- single-label filter produces statistics for a value-enabled label
- multi-label filter with exactly one value-enabled label produces statistics scoped by all labels
- multi-label filter with multiple value-enabled labels suppresses statistics
- smart folder with exactly one value-enabled label produces statistics even when it also contains non-unit labels
- smart folder with multiple value-enabled labels suppresses statistics
- changing a value while the filter is unchanged refreshes statistics
- changing a label unit while the filter is unchanged shows or hides statistics as appropriate
- migration opens a pre-V5 library with existing labels and documents intact
- existing test container helpers and previews include `DocumentLabelValue` so tests do not accidentally run with a partial schema
- value input rejects overlong numbers, excessive fractional digits, exponent notation, `NaN`, and infinity-like strings
- removing a label from the inspector clears value state and cannot recreate the value on submit/focus loss

Add at least one UI or UI-adjacent test in `DocNestUITests` or a focused integration harness:

- launch or construct a library with a value-enabled label and a labeled document
- edit the value through the inline list label chip, if practical
- activate the label filter
- verify the inspector shows label identity/removal controls without a value editor
- verify the contextual list value indicator appears only for the active value-enabled label filter and treats missing values differently from zero
- verify missing value label chips reveal the inline `+ value` affordance
- verify the sidebar statistics footer shows the active value label, always shows filtered statistics, and shows selection statistics only for multi-selection
- verify `0 of N valued` leaves numeric statistics empty instead of dividing by zero
- verify the statistics footer appears and updates after the edit

If direct UI automation proves too brittle, add accessibility identifiers to the value field and statistics footer before writing the test.

Run focused tests while implementing, then follow the repository gate:

```sh
xcodebuild test -project DocNest.xcodeproj -scheme DocNest -only-testing:DocNestTests
xcodebuild test -project DocNest.xcodeproj -scheme DocNest
```

## Documentation Plan

Update requirements documentation when implementing:

- define label units and document-label values under labels
- describe when filter statistics appear
- state that values are manually entered and optional
- describe how users add a value from a missing-value label chip in the document list

Update organization documentation:

- explain that labels can optionally carry units
- explain that statistics describe one active value label at a time, always include filtered documents, and include selected visible documents only for multi-selection
- clarify that values are metadata on the document-label assignment, not on the document globally

Update library format/schema documentation:

- mention the new SwiftData model and schema V5
- mention value rows are supplemental metadata and can be repaired if orphaned

## Implementation Steps

1. Add `DocumentLabelValue`, `LabelTag.unitSymbol`, and schema V5.
2. Add value parsing, formatting, mutation, pruning, and statistics domain helpers.
3. Update label create/edit flows and `ManageLabelsUseCase` merge/delete/remove behavior.
4. Add coordinator-derived statistics for the effective single value-enabled label filter.
5. Add inline list chip value editing for assigned labels with units.
6. Add contextual read-only document-list value indicators and missing-value affordances for the active value-enabled label filter.
7. Add the sidebar statistics footer that shows filtered statistics and adds selected statistics for multi-selection.
8. Add tests for domain behavior, statistics, filter scoping, lifecycle cleanup, invalidation, UI wiring, and migration.
9. Update requirements and supporting docs.
10. Run the required independent AI reviews and full test suite before committing.

## Implementation Phase Instructions

When implementing this feature, follow `AGENTS.md` as the controlling workflow:

- add or update automated tests with the implementation, including domain, migration, coordinator/statistics, and UI or UI-adjacent coverage described above
- update `docs/requirements.md` in the same change because this feature changes app behavior
- update supporting documentation such as `docs/search-and-organization.md` and `docs/library-format.md` where the new label unit/value model affects behavior or schema description
- run the independent AI review sequence required by `AGENTS.md`: start with the fast reviewer, fix findings, rerun until clean, then run the stronger reviewer and fix any findings
- run the full test suite only after both review passes are clean
- commit only after implementation, documentation, reviews, and full tests are complete
- push the completed commit to the remote branch
- create a major release after the pushed implementation is verified

For the major release:

- follow the repository release instructions in `AGENTS.md`
- ensure the working tree is clean before release work
- determine the repository default branch from git/GitHub metadata
- check out the default branch and fast-forward it from origin when possible
- check GitHub for the latest published release before choosing the next version
- use the `YYYY.MAJOR.MINOR` schema
- because this feature explicitly requests a major release, increment the `MAJOR` component for the current release year and reset `MINOR` to `0`, unless the latest release year differs from the current calendar year and the repository release rules require starting the new year line at `YYYY.1.0`
- create the release from the default branch and verify it is marked latest

## Risks and Mitigations

- SwiftData migration risk: verify V4 libraries open cleanly before any UI work is considered complete.
- Partial schema risk: update every `ModelContainer(for:)` test helper, preview container, and root `@Query` ingestion path so `DocumentLabelValue` exists wherever label-value code can run.
- Relationship consistency risk: keep the existing label relationship as assignment truth and prune value rows whenever assignments change.
- Identity stability risk: treat document and label UUIDs as immutable because value rows reference them directly.
- Orphaned value risk: explicitly delete value rows during hard document deletion and add repair coverage for any value rows whose document or label no longer exists.
- Duplicate value risk: enforce one row per document-label pair in the write use case and deduplicate during repair.
- Stale statistic risk: recompute statistics on value and unit metadata changes, not just filtered-document changes.
- Selection latency risk: run statistics as cancellable derived work after selection state updates, using background tasks for expensive calculations.
- Partial save risk: implement destructive unit clearing as one confirmed, atomic use-case operation.
- Merge risk: explicitly test label rename/update paths that merge duplicate label names.
- Formatting risk: separate parsing, persistence, and display formatting so locale-specific UI input does not leak into storage.
- Input abuse risk: reject overlong or non-finite numeric strings before attempting expensive parsing.
- Pill overload risk: keep the split chip compact and limit visible labels with overflow.
- Discoverability risk: missing-value chips must reveal direct `+ value` affordances on hover or selection.
- UI clutter risk: keep aggregate statistics in the sidebar footer; avoid adding another large dashboard panel.
- Scope surprise risk: show filtered and selection statistics side by side instead of requiring users to discover a scope toggle.
- Narrow layout risk: use a compact sidebar grid so both scopes remain readable.
- Performance risk: compute statistics from `filteredDocuments` and the value lookup map, not from repeated SwiftData fetches per row.
- Data-loss risk: clearing a label unit intentionally deletes existing values, so require an explicit warning that includes the affected document count before the deletion happens.

## Independent Review Notes

An independent review pass with a different model found four plan gaps, all incorporated above:

- define uniqueness and cleanup rules for `DocumentLabelValue`, including hard document deletion
- define statistics invalidation on unit/value changes, not just filtered-document changes
- enumerate quick-create label surfaces and decide duplicate-name unit behavior
- add UI or UI-adjacent coverage for inline value editing and the statistics footer

## Open Questions for Implementation

Resolved product decisions:

- Clearing a label's unit deletes existing values after a warning that includes the affected document count.
- Each document-label pair supports exactly one value.
- Units are free-form strings for v1; no ISO currency semantics are required.
- Statistics are displayed on screen only; export/copy behavior is out of scope for v1.
