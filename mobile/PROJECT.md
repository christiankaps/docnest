# DocNest Mobile

**Workflow:** ESTABLISHED

**Maturity:** MVP

## Purpose and current state

A free, native iPhone app for individuals managing hundreds of personal documents. The primary workflows are capturing PDFs, finding them through labels, and sharing them. The experience should be modern, intuitive, and consistent with standard iOS interactions.

Current implementation: a private local PDF library with safe file import, duplicate detection and numbered filenames, a label-first Library home, editable starter/custom labels and multiple assignments, AND/year filtering, manual document dates, Inbox review, PDF viewing and existing-text search, details, rename, bulk sharing/additive labeling, Recently Deleted with 30-day recovery, sharing, PDF export, an optional Face ID/passcode library lock, and a private capture queue. The local icon and English string catalog remain self-contained. Increments 0–3 are finalized; increment 4 is implemented and simulator-verified with physical-iPhone qualification pending. Implementation and verification evidence are recorded in PLAN.md. The remaining capabilities below describe the target product.

The initial delivery is local-only. The project is independent of the desktop app and is not a companion app. Everything required to build it stays inside this folder; reused resources are copied locally.

## Sources of truth

| Subject | Source |
| --- | --- |
| Product scope and accepted behavior | This document |
| Technical boundaries, SDK choices, and unresolved engineering details | [ARCHITECTURE.md](ARCHITECTURE.md) |
| Sequential implementation and verification | [PLAN.md](PLAN.md) |
| Build/run instructions | [README.md](README.md), `project.yml`, `Makefile` |
| Agent operation | [AGENTS.md](AGENTS.md) |

Earlier exploratory mockups are illustrative; this specification governs where their navigation or behavior differs.

## Platform, language, and scope

- iPhone only, minimum iOS 27; build with Xcode 27 or later.
- English interface initially. Prepare interface strings and starter labels for localization; starter-label identity must not depend on translated names.
- Recognize English and German documents, including mixed-language documents. Document language is independent of interface language.
- Local-only, app-private storage. No storage-mode chooser during initial setup.
- No document processing by cloud or external AI services.
- No support for encrypted PDFs, including password entry or password storage.

Cloud synchronization, storage switching, Foundation Models, Siri/Shortcuts, widgets, Spotlight document indexing, and precise OCR word highlighting are deferred. iPad, Android, a desktop companion role, PDF editing/markup, and external live-library editing are outside the initial scope. Similar-looking scans are not deduplicated by appearance; duplicate detection is based on identical PDF content.

## Navigation and document presentation

- Two tabs: Library and Inbox. Settings opens from the Library toolbar.
- Library is label-first, with a visible Inbox count, a separate Years section, and quick Scan and Import PDF actions.
- Lists contain title, labels, and document date, without thumbnails. Default sorting is newest document date first.
- Import date is stored and visible in details only; it is not a sorting or filtering criterion.
- Use a native PDFKit document screen with visible Share and Details actions and in-document search.
- Native swipe actions provide Labels and Delete. A long-press menu provides Share, Rename, Labels, and Delete; expose actions as their underlying functionality becomes available.
- Native Select mode supports sharing several PDFs and assigning labels to several documents. Assignment adds labels without removing existing ones.
- Use native controls, readable text, Dynamic Type, VoiceOver, dark appearance, and accessible touch targets throughout.

## Capture and inbox

- Import PDF copies using the system document picker or by sharing from Mail and other apps.
- Scan multiple pages into one PDF using native edge detection and crop adjustment. Camera capture is core initial functionality.
- Provide a Home Screen app-icon long-press action named Scan Document that opens the scanner on a cold launch or while the app is running.
- All capture routes use the same validation, naming, duplicate handling, and inbox rules.
- Reject encrypted PDFs with a clear explanation requesting an unencrypted copy. Leave source files untouched and create no partial library entry. Unreadable/corrupt inputs and failed writes must likewise fail clearly without destroying existing data.
- Detect identical PDF content before creating another document. Preserve existing metadata and offer to open the existing document when access is unlocked. Locked capture must not disclose or open existing library content.
- Save captures to the Inbox without requiring labels. The Inbox contains documents awaiting review, not a separate storage location.
- Done removes a document from the Inbox while retaining it in the library. A reviewed document may have no labels.

## Processing and suggestions

- Extract existing PDF text and use on-device OCR where needed. Capture, viewing, sharing, and manual labeling remain usable while processing is pending.
- Show Processing in the Inbox, persist pending work, and resume interrupted work later. Do not promise immediate completion while the app is closed.
- OCR failure does not invalidate a usable PDF. Keep viewing, sharing, and manual labeling available, show the failed state, and offer Retry OCR.
- Processing completion/retries never duplicate documents, overwrite manual edits, or reset Done status. New suggestions remain available for explicit acceptance.
- Initial smart label suggestions use document text and previous labeling choices. Users label manually or easily accept suggestions; ordinary labels are never applied automatically.
- Foundation Models is a future enhancement only if comparative testing demonstrates meaningful benefit. No cloud fallback.
- OCR never generates or changes scan filenames. Value-label amounts are entered manually, not inferred by OCR.

## Labels, years, and search

- Documents may have multiple labels. Labels organize views rather than imposing filesystem folders.
- Editable starter set: Invoices, Banking, Insurance, Taxes, Health, Home, Work, Vehicles, Contracts, Receipts. Users may add, rename, or remove labels. Initialize the starter set once; renamed or deleted starter labels stay changed across relaunch. Removing a label never deletes its documents.
- All selected ordinary labels combine using AND.
- Derive a virtual year label from each document date. At most one year may be selected; choosing another replaces it, and clearing it removes the year restriction.
- The selected year, every selected ordinary label, and search text combine using AND.
- Full-text search is secondary to labels and stays inside DocNest; do not index document titles/content in Spotlight.
- Search in image-only scanned PDFs shows matching OCR snippets and navigates to the corresponding page. Preserve the original PDF; precise OCR word highlighting is deferred.

## Dates and filenames

- Each document has an editable document date distinct from its import date and filesystem dates.
- Infer the document date from content, preferring issue/invoice date over payment due date. Flag uncertain results for review. If no reliable date is found, suggest the import date and flag it.
- Saving a document date marks it as manually confirmed, even when unchanged. Date edits update the virtual year but never rename the file. Done alone does not confirm a fallback date. Late results respect manual edits and review status.
- Preserve imported filenames unless a name collision requires a suffix.
- Scan names use the local capture date and literal suffix `DocsNest_Scanner`: `YYYY-MM-DD_DocsNest_Scanner.pdf`. The spelling and suffix are fixed filename text, not an organizational label. OCR-derived document dates have no effect on this name.
- For a distinct document with a colliding filename, append the next available `_2`, `_3`, etc. before `.pdf`. The suffix is permanent and visible in both filename and library title. Sharing/export uses the same name.
- Apply collision handling to imports, scans, manual renames, and restore. Preserve the first document's name and never renumber existing documents. Identical-PDF detection takes precedence over creating a numbered duplicate.
- Use stable internal document IDs independently of filenames. Users can explicitly rename documents within the app.

## Value labels

A label with an optional short unit, such as `€`, `USD`, `kg`, or `h`, enables one optional manual numeric value per document-label assignment. Multiple value labels on a document hold independent values. Starter labels have no preset units; virtual year labels cannot have values.

- Normalize unit whitespace and allow up to 12 characters.
- Support decimal values, including negatives, with up to 30 total digits and 6 fractional places. Use canonical decimal storage and decimal arithmetic; parse/display according to numeric locale. Reject invalid/nonfinite numbers and scientific notation.
- Missing is distinct from zero. Clearing a value retains its label; removing an assignment removes its value. Deleting a label removes assignments/values without deleting documents.
- A unit change with existing values requires confirmation explaining that numbers stay unchanged and no conversion occurs.
- Clearing a unit is different: after confirmation showing the affected document count, delete its existing values.
- Show a connected label/value chip, such as `Invoices | 84.20 €`. A missing value has a visible + value segment.
- Tapping the value segment opens a native editing sheet with label, unit, value, Save, Cancel, and Clear where applicable. Keep label removal and document opening as separate actions.
- Show statistics only when exactly one unit-enabled label is in the active filter context. Other labels, the selected year, and search may narrow the scope.
- Name the active label/unit and show document count, valued count, missing count, sum, average, minimum, maximum, and median. Missing values are excluded from numeric aggregates; zero is included. With no valued documents, aggregates are unavailable rather than zero.
- Always show filtered-document statistics. Also show selected-visible-document statistics when more than one visible document is selected. Never aggregate across different labels or units.
- Use a compact list summary that opens a sheet with all statistics. Calculation must not block selection or document opening.
- Preserve values through renaming, soft deletion/recovery, and backup/restore. Future cloud operations must preserve them too.

## Private storage and library lock

- Store the live library privately; it must not be visible in Files or exposed for external in-place editing. All library changes go through DocNest.
- Imports are copies. Sharing, PDF export, and library backup create separate copies. Changes to sources or exported files never modify the library.
- Do not implement external rename/replacement/deletion reconciliation, folder watching, or a Files provider.
- Offer an optional Face ID library lock with iPhone passcode fallback. Protect library/inbox browsing and review.
- Camera scanning and incoming shared-PDF capture do not require authentication. They may save to the Inbox without exposing existing documents or unlocking the library.
- Relock immediately when leaving the app, without a grace period. Allow system share-sheet/file-picker tasks to finish; returning to protected content after leaving requires authentication. Transient inactivity alone must not interrupt the task.
- When the library lock is enabled, cover document content in app-switcher previews with a neutral DocNest cover.

## Sharing, deletion, and backup

- Sharing is a primary workflow. Use the native share sheet to share original PDF contents, with individual and multiple-document support. Also support standalone PDF export.
- Keep deleted documents in Recently Deleted for 30 days, with recovery during that period. Exclude them from active browsing/search/statistics. Cleanup must resume safely when execution is available.
- Export the whole library as a versioned backup containing PDFs and durable metadata, including filenames, dates, labels, units, values, and review state. The exact format and treatment of Recently Deleted content are engineering details to settle in the backup increment.
- Restore on a new device or merge into an existing library. Preserve existing documents; skip identical PDF payloads, combine their labels, and keep their current names.
- Fill missing document-label values from backup. Zero counts as present. If values differ, keep the current value, report the conflict, and allow explicit use of the backup value. Never add conflicting amounts together.
- Keep current document dates and units when the backup differs; report conflicts and allow explicit selection of the backup version. Resolve unit conflicts before applying affected values; changing a unit never performs conversion.
- Preserve the last valid library on failed, corrupt, or interrupted import/restore operations. Do not silently discard unresolved metadata conflicts.

## Deferred scope

These do not block local delivery and require their own finalized increments later:

- Private iCloud synchronization across the user's iPhones and access on a new iPhone. Keep the library out of Files.
- Local/iCloud choice when cloud support exists. Automatically download all PDFs, report progress, and track actual offline availability.
- Verified storage-mode switching in Settings. Copy and verify before completing; download all documents before switching to local-only. Retain cloud copies until explicit deletion. Define conflicts when rejoining a retained cloud library.
- Foundation Models, only after demonstrated improvement over the initial suggestion baseline, entirely on-device.
- Siri/Shortcuts, widgets, Spotlight document indexing, and precise OCR word highlighting remain outside the initial delivery; no implementation commitment is made here.

## Acceptance and working conventions

The local delivery must support the specified capture → review → label/year retrieval → share workflow, value labels, privacy, and recovery for hundreds of personal PDFs. Define representative page/file-size fixtures and measurable responsiveness targets during implementation; no unverified performance promise is made.

Use `make help` and `make verify` from this folder. The gate builds and runs library safety/resource tests and simulator UI checks; extend it as behavior is introduced. Physical-device checks remain required for camera and authentication behavior. Details and per-increment acceptance are in PLAN.md.

Use Git for coherent verified changes, preserve unrelated work, and integrate directly on main without feature branches or pull requests. Prefix mobile commits with `[mobile]`. Commit and push to main after every verified increment as part of finalization, without waiting for another request; finish this before starting the next increment. App distribution/publishing requires separate explicit authorization. Keep INBOX.md user-owned; DECISIONS.md and LESSONS.md are temporary queues, not additional product specifications.
