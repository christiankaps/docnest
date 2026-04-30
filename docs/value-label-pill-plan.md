# Value Label Pill Plan

## Goal

Show a value-enabled label's document-specific value directly inside the document label pill, using the split-pill concept:

```text
[ Invoice | 1,240 € ]
```

The label name remains the identity surface. The value becomes a secondary trailing segment that clearly belongs to the document-label pair.

Labels should also become more prominent in the document list: show the label strip as the second visible column immediately after the document name, so document identity and classification are read together.

## Current Context

- `LabelChip` in `DocNest/Shared/Design/LabelChip.swift` renders label identity chips.
- `DocumentListView` renders label chips through `DocumentLabelStrip` and `RemovableLabelChip`.
- Label values already exist as `DocumentLabelValue` rows, keyed by document ID and label ID.
- `LibraryCoordinator` already has active-filter value lookup for the separate `Value` column, but pill rendering needs values for all labels assigned to the visible document, not only the active statistics label.
- Values should be edited inline in the document list label pill. The inspector should keep label assignment/removal, but should no longer be the value editing surface.

## UX Concept

### List Placement

Move labels into a dedicated second column after the document name column.

Target column order:

```text
Document | Labels | Value | Size | Added | ...
```

Rules:

- the document name remains the primary first column
- the labels column follows immediately after the name and gets enough width to show at least the first meaningful split pill on common window sizes
- the labels column uses the new split-pill rendering for value-enabled labels
- the existing contextual `Value` column remains separate for now, because it supports sorting/scanning the active statistics label
- when horizontal space is constrained, keep document name and labels visible before lower-priority metadata columns
- update the adaptive optional-column hide order so labels stay visible with the document name before lower-priority metadata; hide pages, size, contextual value, and secondary date metadata first
- avoid duplicating label pills in their previous location once the dedicated labels column is introduced
- preserve row height and existing selection behavior

### Default Filled State

Render value-enabled labels with a split pill when the document has a value for that label:

```text
[ 🧾 Invoice | 1,240 € ]
```

Visual rules:

- left segment uses the existing label chip treatment
- right segment uses the same label hue at lower emphasis
- value text uses monospaced digits for scanability
- use a subtle inner divider or small seam between name and value
- use a soft rounded-rectangle chip instead of the current fully capsule-shaped pill; target about 6 px corner radius in compact rows
- keep the outer shape as one connected chip so the value reads as part of the label, not a second label
- preserve existing label icon behavior
- keep compact chip height unchanged in document rows

### Empty Value State

For a value-enabled label without a document value, do not show a permanent empty segment by default. The normal chip stays quiet:

```text
[ 🧾 Invoice ]
```

On hover or row selection, reveal a subdued trailing affordance:

```text
[ 🧾 Invoice | + value ]
```

Rules:

- show `+ value` only for labels that have a unit but no stored value
- use secondary/tertiary styling so missing values do not dominate the row
- clicking the `+ value` segment switches the pill into inline value editing
- do not render `0` as empty; `0 €` is a filled value

### Editing State

Use concept 4 as the editing interaction for the split pill. The list row becomes the value editing surface so the user can add or correct a document-label value without leaving the document list.

Filled value:

```text
[ 🧾 Invoice | 1,240 € ]
```

Hover or keyboard focus on the value segment:

```text
[ 🧾 Invoice | 1,240 € ✎ ]
```

Empty value on hover, keyboard focus, or selected row:

```text
[ 🧾 Invoice | + value ]
```

Rules:

- the value segment is a discrete button inside the pill when not editing
- clicking a filled value or `+ value` changes that chip into a compact inline text field in the value segment
- pressing Return commits the value; leaving the field commits if the value changed; Escape cancels and restores the previous value
- entering an empty string clears the value and returns the chip to the empty behavior
- invalid input keeps the field open, marks the chip with error styling, and exposes the validation message via help/accessibility
- inline editing is scoped to one document-label pair; bulk value editing is not introduced by this feature
- the value button must consume its click cleanly so row-level selection, double-click, rename, preview, or other row gestures do not also fire
- row-level gestures should still work when the user clicks outside the value segment

### Hover and Remove Interaction

The current removable chip shows an `xmark.circle.fill` on hover. The split pill needs stable hit zones:

- label/name segment: existing label behavior
- value segment: enter inline value editing
- remove button: remains outside the capsule, as it does today
- when both `+ value` and remove are visible, keep enough spacing so the delete target is not confused with the value target

### Multiple Value Labels

Each label owns its own value segment:

```text
[ Invoice | 1,240 € ] [ Hours | 3.5 h ] [ Tax ]
```

Never combine values from multiple labels in a single chip or row-level badge.

## Data Flow

Add a document-label value lookup suitable for row rendering:

- derive `[DocumentID: [LabelID: String]]` or `[DocumentLabelValueKey: String]` in `LibraryCoordinator`
- build it from `allLabelValueSnapshots` when label values are synced
- keep it cheap for row rendering; no per-row SwiftData fetches
- expose a read-only helper such as `formattedLabelValue(for document: DocumentRecord, label: LabelTag) -> String?`
- return `nil` for missing values, including missing or invalid decimal strings

The current active-statistics lookup can remain for the `Value` column until that column is retired or reworked.

## Component Changes

### `LabelChip`

Extend `LabelChip` rather than creating a separate duplicate style:

- add optional `valueText: String?`
- add optional `showsMissingValueAffordance: Bool = false`
- add optional `onValueTap: (() -> Void)?`
- preserve existing initializer defaults so current call sites continue to compile

Render as:

- base `HStack` for icon and name
- optional divider when a value or missing affordance is visible
- trailing value segment with monospaced digits
- use rounded rectangles with a modest corner radius instead of `Capsule`, without increasing row height

If `LabelChip` becomes too broad, introduce a small internal `LabelChipValueSegment` helper in the same file.

### `DocumentLabelStrip`

Change `DocumentLabelStrip` inputs from only labels to a document-aware model:

```swift
struct DocumentLabelChipState: Identifiable {
    var id: PersistentIdentifier { label.persistentModelID }

    let label: LabelTag
    let valueText: String?
    let isValueEnabled: Bool
    let isActiveStatisticsLabel: Bool
}
```

The identity can be the label's persistent model ID because a document cannot contain the same label twice. If implementation code cannot use `PersistentIdentifier` directly in this helper, use an equivalent stable label ID derived from the assigned `LabelTag`.

The strip should:

- keep the current visible label limit initially
- preserve user-defined sort order within each visibility priority group
- when overflow exists, prefer visible slots in this order:
  - active statistics label, when it is assigned to this document
  - value-enabled labels with document values
  - value-enabled labels missing values, but only while the row is hovered or selected
  - remaining labels in normal sort order
- pass `valueText` and hover-selected missing state into `RemovableLabelChip`

The overflow chip remains compact, but its accessibility/help text should include hidden value context, for example `2 hidden labels, 1 missing value`. Clicking the overflow chip can keep the existing behavior if one exists, or remain informational if there is no current action.

### `RemovableLabelChip`

Add value-related parameters:

- `valueText: String?`
- `rawValue: String?`
- `isValueEnabled: Bool`
- `onValueCommit: ((String) throws -> String?)?`

Use its existing hover state to reveal `+ value` for missing values. When editing, replace the value segment with a compact text field and commit through `ManageLabelValuesUseCase`. Keep remove behavior as-is.

### Inspector Relationship

Remove document-label value editing from the inspector to avoid two competing editing locations. The inspector should still show assigned labels and allow assignment/removal, but value entry belongs to the list chip.

## List Column Relationship

Keep the existing `Value` column for now because it is useful for sorting/scanning the active filtered value. The pill value is per-label and can show multiple values, while the column is contextual to the active statistics label.

The new `Labels` column should sit immediately after the document name. This makes the label system more central to the list view without overloading the name cell. If the table currently renders labels inside the name/details cell, remove that inline rendering after the dedicated column is in place.

The responsive column policy must match that emphasis. `Labels` should be treated as a core list column alongside the document name: hide pages, size, contextual value, and secondary date metadata before compressing the document and labels columns.

After the pill feature ships, reassess whether the `Value` column should become hidden by default or remain opt-in.

## Empty Case Details

Empty values must be treated as missing metadata:

- normal idle pill: no value segment
- hovered or selected row: show `+ value`
- statistics continue counting the document as missing for that label
- no average/sum/min/max/median calculations include missing values
- clearing an existing value returns the pill to the empty behavior
- clearing the label unit removes value support and removes the `+ value` affordance

Accessibility:

- expose the outer split pill as a label group, not as unrelated pieces of text
- filled pill description: `Invoice label, value 1,240 €`
- missing pill description: `Invoice label, no value`
- value segment button label: `Edit Invoice value, 1,240 €`
- missing value button label: `Add Invoice value`
- remove button label: `Remove Invoice label`
- keyboard order should be label group, value action when present, then remove action
- avoid duplicated VoiceOver output by hiding purely decorative divider/icon elements from accessibility when needed

## Visual Specification

Compact row chip:

- outer capsule height: current compact chip height
- shape: rounded rectangle, not a full capsule
- corner radius: about 6 px for compact row chips, with the same radius shared by name and value segments
- name horizontal padding: current compact padding
- divider: 1 px, label color at about 20-30% opacity
- value segment padding: 6-8 px horizontal
- filled value foreground: primary or label color mixed toward primary
- missing affordance foreground: secondary
- value segment background: label color opacity around 10-14%, slightly different from name background
- use `.monospacedDigit()` for filled values
- use `.lineLimit(1)` and `.minimumScaleFactor(0.8)` for long values

Dark mode:

- increase divider opacity slightly
- avoid pure white value backgrounds
- keep value readable over selected row backgrounds

## Edge Cases

- document has multiple value-enabled labels with values
- document has multiple value-enabled labels with missing values
- value is zero
- value is negative
- value has many digits or fractional digits
- unit is long but valid
- label has icon and value
- chip is shown in a selected row
- chip is hovered while remove button is visible
- labels column is narrow and must show one useful pill plus overflow without clipping controls
- narrow window triggers optional-column hiding; labels remain visible until lower-priority metadata is hidden
- hidden label overflow hides a valued label
- hidden label overflow hides a missing value label
- active filter has multiple value-enabled labels; pill values still render per assigned label, while statistics remain suppressed
- value changes inline while row remains visible
- label unit is cleared while row remains visible
- clicked value segment belongs to a document inside an existing multi-selection
- value segment click occurs inside a row that also has selection or double-click gestures
- inline value edit loses focus after a valid change
- inline value edit receives invalid numeric input

## Performance

- build row value lookup once in coordinator ingestion/sync, not in each chip
- avoid `first(where:)` scans across all values for every visible label
- keep formatting deterministic and cheap; cache formatted string if needed
- no background statistics recompute should be triggered solely by hover state

## Testing Plan

Add focused tests where practical:

- domain/coordinator test for document-label value lookup returning filled and missing states
- unit test that zero formats as a value, not missing
- UI-adjacent test or preview assertion that `LabelChip` renders:
  - label only
  - label with value
  - label with missing affordance
  - label with icon and value
- interaction test, if stable, for clicking a filled value entering inline edit mode
- interaction test, if stable, for clicking `+ value` entering inline edit mode
- commit test for inline value save and clear behavior, preferably through the same use case path
- test or preview for hover/selected empty state revealing `+ value`
- test that overflow help text reports hidden value-enabled labels and missing values
- test that clearing a label unit while a row is visible removes the value segment and missing affordance
- UI-adjacent test or snapshot for the document list column order showing labels directly after the document name

Run:

```sh
xcodebuild -project DocNest.xcodeproj -scheme DocNest build
xcodebuild test -project DocNest.xcodeproj -scheme DocNest -only-testing:DocNestTests
```

Run the full suite after independent reviews are clean if implementing as a code change.

## Documentation Updates

Update:

- `docs/requirements.md`: label pills can show document-label values inline
- `docs/search-and-organization.md`: value display belongs to the document-label pair
- any existing plan notes that say values are only shown in a separate contextual column

## Implementation Steps

1. Add coordinator value lookup for arbitrary document-label pairs.
2. Extend `LabelChip` with optional split value segment and missing affordance.
3. Update `DocumentLabelStrip` and `RemovableLabelChip` to pass value state.
4. Move the document label strip into a dedicated labels column immediately after the document name column.
5. Implement concept 4 editing: value segment and `+ value` switch to an inline text field, commit on Return/blur, cancel on Escape, and show validation errors in place.
6. Remove value editing rows from the inspector while keeping label assignment/removal there.
7. Keep the existing Value column unchanged.
8. Add focused tests and previews.
9. Update requirements and organization docs.
10. Run the AGENTS.md review and test workflow before committing.
