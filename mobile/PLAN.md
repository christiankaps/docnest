# Implementation plan

[PROJECT.md](PROJECT.md) defines accepted behavior; [ARCHITECTURE.md](ARCHITECTURE.md) records technical boundaries and engineering decisions. Increments 0–2 are finalized. Increment 3 is next and has not started.

Implement increments in order. Check an item only after implementation and required verification. Finalize each increment by completing every checkbox, recording its outcome, checks, and remaining limitations here, and committing and pushing its changes to main before starting the next. Commit and push after every increment without waiting for another request. A build alone does not verify product behavior. Add meaningful automated checks to `make verify` as behavior is introduced; perform required device checks before finalization.

## 0. Hello World foundation — finalized

- [x] Create an independent iPhone-only SwiftUI app targeting iOS 27.
- [x] Copy the master app icon locally and prepare its iOS asset.
- [x] Add an English string catalog and reproducible local build commands.
- [x] Verify a simulator build and launch the Hello World screen; record the outcome.

Outcome, 2026-10-10: `make verify` succeeded with Xcode 27. The app is iPhone-only. Installed and launched on the iOS 27 iPhone 18 Pro simulator; visually confirmed the DocNest title and Hello World screen. Physical-device signing is not configured. The starter has no App Intents dependency, so Xcode emitted its standard metadata-skip warning.

## 1. Private local PDF library — finalized

- [x] Choose and document local persistence, versioned schema, and private file layout. Model stable document IDs, filenames, document/import dates, date provenance, review state, and independent processing state. Keep cloud infrastructure out of this increment.
- [x] Implement recoverable file/metadata writes and startup recovery; keep the library absent from Files and unavailable for external in-place editing.
- [x] Import PDF copies through the system picker. Validate inputs, reject encrypted/corrupt PDFs clearly, leave sources untouched, and avoid partial visible entries on failure.
- [x] Detect identical PDF content before creating another document; preserve existing metadata and offer the existing document. For distinct name collisions, permanently append `_2`, `_3`, etc. before `.pdf`, consistently in the filename and title. Never overwrite or renumber an existing document.
- [x] Establish Library/Inbox tabs and Settings entry, basic title/date lists without thumbnails, an initial flagged document-date fallback, and import time in details only.
- [x] Add PDFKit viewing, existing-text in-document search, visible Share/Details, and single-document original-PDF sharing/export using independent copies and the stored filename.
- [x] Establish a synthetic resource corpus for hundreds of PDFs and record representative file sizes/page counts and initial load/open timings.
- [x] Verify relaunch persistence, interrupted writes/imports, resource failure, duplicate/name safety, source/export independence, and private storage. Run `make verify`, record evidence and outcome, and finalize this increment.

Outcome, 2026-10-11: implemented the private library, versioned per-document JSON records, staged/atomic publication, exact-content deduplication, permanent filename numbering, system PDF import, Library/Inbox and Settings, PDFKit viewing/search, details, original-PDF sharing, and native PDF export. All dates are flagged import-date fallbacks; labeling, date editing, and review completion remain increment 2.

Verification: `make verify` passed 10 unit tests and 2 UI tests on the iOS 27.0 iPhone 18 Pro simulator. Coverage includes relaunch, failed writes/out-of-space injection, interrupted-import recovery, missing/corrupt/future metadata, encrypted PDFs (including empty-password encryption), invalid inputs, symbolic-link rejection, duplicate/name safety, source/export independence, search page/range mapping, private-storage configuration, viewer navigation/details/search, export filename and cancellation, sharing, Settings, and import-picker presentation. Library, Details, share-sheet, and export screenshots were inspected. `make build CONFIGURATION=Release` also passed; test launch routing/fixtures are debug-only. The standard App Intents metadata-skip message remains informational.

Resource baseline: 300 synthetic PDFs (250 text PDFs with 1/2/10 pages, 50 raster-heavy PDFs with 1/5/20 pages), 7,953–2,383,338 bytes each, 121,361,763 bytes total. The raster corpus reuses a synthetic image within each PDF. Final simulator run: corpus generation/import 4.27 s; library reload 0.101 s; largest-file open plus first-page render 0.005 s. These are simulator baselines, not physical-device guarantees; refine realistic scan diversity and device performance targets in increments 6 and 10.

Limitations: signing and physical-device checks are not configured in this increment. Hardware file protection, camera, and authentication need their scheduled device verification. Native system picker presentation is UI-tested; library import/export content safety is covered by service tests. No later increment was started.

## 2. Labels, dates, and inbox review — finalized

- [x] Extend versioned metadata without losing existing documents, IDs, filenames, or original bytes. Make metadata edits and label deletion atomic and recoverable after interruption.
- [x] Add stable label IDs and the editable English starter set, ready for localization. Seed it once; preserve renamed/deleted starter labels across relaunch. Support creation, renaming, deletion, and multiple labels per document; deleting a label must not delete documents.
- [x] Build the label-first Library home with Inbox count, Years, and Import action. Add Scan when capture exists in increment 5.
- [x] Implement manual labeling, editable document dates, and Done. Reviewed documents remain in the library even without labels. Record manual date provenance for future OCR precedence; Done alone does not confirm a fallback date.
- [x] Derive virtual years from document dates; allow one selected year, replace it when another is chosen, and support clearing it. Combine all selected labels and the year with AND.
- [x] Sort newest document date first; keep import time out of sorting/filtering. Date changes update the virtual year without changing filenames.
- [x] Resolve navigation by stable document ID so edits immediately update open views, filters, year sections, and Inbox counts.
- [x] Verify existing-library compatibility, failed/interrupted metadata writes, starter customization persistence, label deletion safety, AND combinations, date/year changes, review persistence, and Done without labels. Run `make verify`, record outcome, and finalize this increment.

Outcome, 2026-10-11: implemented a label-first Library home with document/Inbox counts and Years, editable localization-ready starter/custom labels, multi-label assignment, AND/year filters, manual document dates, and Done review completion. Original PDFs and increment-1 import records remain unchanged; a versioned atomic organization snapshot owns edits and label assignments. Stable-ID navigation resolves live metadata so changes immediately update Details, lists, years, and Inbox. Starter customizations survive relaunch, including deleting the entire set. Manual date confirmation is independent of Done and preserves filenames.

Verification: `make verify` passed 16 unit tests and 4 UI tests on the iOS 27.0 iPhone 18 Pro simulator. New coverage includes increment-1 library compatibility, metadata write failure and simulated interruption, corrupt/future organization data, starter identity and customization persistence, deletion of assigned labels, multi-label AND/year filters, date-based sorting, duplicate preservation after editing, immediate model refresh, Done without labels, and native create/rename/delete, date editing, filtering, and review/relaunch flows. A focused review/filter UI rerun passed after fixing synthetic import dates to make year checks independent of the simulator clock. `make build CONFIGURATION=Release` passed. Inspected screenshots of Library, multiple-label selection, date editing, live Details, year selection, and filtered results. The existing 300-PDF resource check passed (reload 0.099 s; largest PDF open/render 0.013 s on the simulator).

Limitations: OCR date extraction and label suggestions remain increments 6–7; dates use a flagged fallback until manually confirmed. Physical-device camera/authentication checks remain in their scheduled increments. No later increment was started.

## 3. Document management and local recovery

- [ ] Add explicit rename using the shared collision policy; preserve document identity and original PDF bytes.
- [ ] Add native Select mode for bulk original-PDF sharing and additive label assignment. Preserve existing labels and make the selection scope clear.
- [ ] Add Labels/Delete swipe actions and Share/Rename/Labels/Delete context menus.
- [ ] Implement Recently Deleted, recovery, and 30-day cleanup that resumes when execution is possible. Exclude deleted documents from active browsing/search and retain their metadata for recovery.
- [ ] Verify rename collisions, multi-item filenames/sharing, bulk-label preservation, deletion/recovery, and retention with a controllable clock. Run `make verify`, record outcome, and finalize this increment.

## 4. Library lock and capture boundary

- [ ] Add optional Face ID authentication with device-passcode fallback for Library, Inbox, and review.
- [ ] Relock immediately on leaving the app and require authentication on returning to protected content. Let active system share/picker tasks finish and avoid interrupting them on transient inactivity.
- [ ] Cover protected content in app-switcher snapshots with a neutral DocNest cover when the lock is enabled.
- [ ] Establish a restricted capture route that can accept new payloads without unlocking or exposing existing documents. Define staging/file-protection choices for the capture increment.
- [ ] Verify lifecycle and navigation bypass cases, including staged capture input and locked duplicates. Test authentication and snapshots on a physical iPhone. Run `make verify`, record outcome, and finalize this increment.

## 5. Camera and incoming shared PDFs

- [ ] Add the share extension and durable App Group handoff; document signing/configuration locally. Reuse the library's validation, deduplication, naming, and review rules.
- [ ] Add native multipage document scanning with edge detection and crop adjustment; save one PDF to the Inbox.
- [ ] Name scans `YYYY-MM-DD_DocsNest_Scanner.pdf` using local capture date and the fixed suffix, with numbered collisions. Never derive scan names from OCR or later document-date changes.
- [ ] Add Library Scan and the localized Home Screen Scan Document quick action for cold launch and running-app activation.
- [ ] Allow scanner and incoming-share capture without authentication. Save safely without unlocking the library or disclosing existing content, including duplicate results; authenticate before review.
- [ ] Verify shared encrypted/corrupt inputs, interruption/relaunch recovery, same-day scans, cancellation, and locked/unlocked routing. Test Mail sharing and multipage scanning on a physical iPhone. Run `make verify`, record outcome, and finalize this increment.

## 6. On-device OCR, document dates, and search

- [ ] Extract PDF text and run on-device OCR where needed for English, German, and mixed-language documents. Store derived results by page without rewriting originals.
- [ ] Persist bounded processing/retry work, show Processing, and resume after interruption. Keep capture/view/share/manual edits usable. OCR failure leaves valid PDFs usable and offers Retry OCR.
- [ ] Infer issue/invoice dates ahead of due dates, flag uncertain/fallback dates, and respect manually edited dates. Late completion/retry must preserve identity, manual metadata, and Done status.
- [ ] Add library full-text search combined with all selected labels and the selected year using AND.
- [ ] Add scanned-document search snippets that navigate to corresponding PDF pages. Defer precise OCR word highlighting.
- [ ] Verify multilingual/ambiguous dates, page mapping, failure/retry, late-result precedence, and filename stability. Measure processing/search responsiveness against the corpus and define measurable targets for final qualification. Run `make verify`, record outcome, and finalize this increment.

## 7. Smart label suggestions

- [ ] Implement a single local text/history-based suggestion pipeline using document text and previously accepted labeling choices. Keep Foundation Models and cloud services out of the initial implementation.
- [ ] Make suggestions easy to accept individually; never auto-apply ordinary labels. Keep manual labeling available and do not infer value-label amounts.
- [ ] Preserve manual choices and Done when suggestions arrive late; make new suggestions available without reopening the Inbox item automatically.
- [ ] Evaluate repeatable synthetic English/German paperwork and recurring issuers; record suggestion usefulness and limitations. Verify acceptance and late-result behavior. Run `make verify`, record outcome, and finalize this increment.

## 8. Value labels and statistics

- [ ] Extend/version persistence with optional normalized label units (up to 12 characters) and one optional decimal per document-label assignment. Keep starter units empty and prohibit values on virtual years.
- [ ] Implement locale-aware negative/positive entry and display, canonical decimal storage/arithmetic, up to 30 total digits and 6 fractional places, and invalid/nonfinite/scientific-notation rejection. Distinguish missing from zero.
- [ ] Add connected label/value chips and a visible + value segment; open a native Save/Cancel/Clear sheet. Keep document opening and label removal separate; support negative entry accessibly.
- [ ] Preserve the label when clearing a value; remove values with assignments/labels. Confirm unit changes with existing values without conversion; confirm unit clearing with the affected count before deleting values. Cancellation must preserve all data.
- [ ] For exactly one unit-enabled label in the active filter, show a compact statistics summary opening a sheet: document/valued/missing counts, sum, average, minimum, maximum, and median. Other labels, year, and search narrow the scope.
- [ ] Always calculate filtered statistics; also show selected-visible statistics when more than one visible document is selected. Exclude missing values and deleted documents; show unavailable aggregates when no values exist. Never mix labels/units or block interaction.
- [ ] Verify numeric boundaries/precision, locale entry, zero/missing, confirmation cancellation, statistics scopes, and persistence through rename/deletion/recovery. Run `make verify`, record outcome, and finalize this increment.

## 9. Whole-library backup and restore

- [ ] Define/document a versioned backup manifest and payload format, label identity matching, and explicit Recently Deleted coverage. Include PDFs, filenames, dates, labels, units, values, and review state.
- [ ] Export a separate whole-library backup and restore into an empty or existing library. Validate before mutation and preserve the last valid library on corruption, interruption, resource failure, or unsupported encrypted payloads.
- [ ] Reuse exact-content deduplication and filename collision handling. Skip identical PDF payloads, combine labels, and retain existing names.
- [ ] Fill missing values from backup; treat zero as present. Keep/report differing current values, document dates, and units, and allow explicit selection of the backup version. Resolve unit conflicts before applying related values without conversion or summing amounts.
- [ ] Keep conflict reports actionable; make incomplete/failed restores clear without silently dropping data or unresolved conflicts.
- [ ] Verify full round-trip, fresh-device restore, merge/idempotence, renamed/colliding files, unit/value/date conflicts, and malformed/interrupted input. Run `make verify`, record outcome, and finalize this increment.

## 10. Local delivery qualification

- [ ] Verify the full capture → review → label/year/search retrieval → share workflow with hundreds of representative personal PDFs, including value labels, recovery, and backups; meet the recorded responsiveness/resource targets.
- [ ] Check VoiceOver, Dynamic Type, dark appearance, accessible touch targets, English strings, localized starter identity, and discoverability of primary actions.
- [ ] Complete regression and physical-device checks for scanner, quick action, share extension, authentication, lifecycle, privacy, and recovery.
- [ ] Verify no external document processing, Files-visible library, parent-folder build dependency, or private data in fixtures.
- [ ] Document reproducible builds, signing, entitlements, backup compatibility, test evidence, and known limitations. Prepare free distribution; publishing remains a separately authorized action.
- [ ] Run the complete `make verify` gate, record final acceptance and outcome, and finalize local delivery before beginning a later phase.

## Deferred work — outside local delivery

Start only after increment 10 is finalized. Define detailed checkbox increments and acceptance criteria before implementing these capabilities; finalize each before starting its successor.

- [ ] Evaluate private iCloud synchronization for both metadata and PDFs, including schema, account behavior, offline edits, deletion, conflicts, and new-iPhone recovery. Verify with two devices before finalizing this phase.
- [ ] Add explicit Local only/iCloud setup, sync status, and automatic download of all PDFs with truthful offline availability, progress, resumable transfers, and storage-failure handling. Verify and finalize before storage switching.
- [ ] Add verified Settings storage switching: copy/verify before completion, download everything before local-only, retain cloud copies until explicit deletion, and resolve rejoining-cloud conflicts. Verify interrupted switching and preserve dates/labels/values/review state; record finalization.

Foundation Models remains a separate optional evaluation after local delivery: adopt only on demonstrated improvement over the local suggestion baseline, with processing entirely on-device. Siri/Shortcuts, widgets, Spotlight, and precise OCR highlighting have no implementation commitment.
