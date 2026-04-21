# DocNest Codebase Cleanup — Todo

Findings from comprehensive codebase analysis. Sorted by priority (bugs/correctness first, then performance, then code quality).

---

## Priority 1 — Bugs & Correctness

- [x] **Possibly inverted deletion mode logic in `LibraryCoordinator`** (`LibraryCoordinator.swift:~348`)
  - Verified: logic is correct. When `libraryURL == nil`, only model removal is possible (`.removeFromLibrary`); when available, stored files are also deleted (`.deleteStoredFiles`). False positive.

- [x] **Silent error swallowing in `ExtractDocumentTextUseCase`**
  - Fixed: Added `OSLog` logging for extraction failures. Errors are now caught and logged instead of silently returning `nil`.

- [x] **Silent error swallowing in `ExportDocumentsUseCase`**
  - Fixed: Added `OSLog` logging for copy failures in both single and bulk export. Single-document export now returns an `ExportDocumentsResult` with failure details instead of silently discarding the error with `try?`.

---

## Priority 2 — Performance

- [x] **Synchronous PDF loading in `PDFViewRepresentable`** blocks the main thread
  - Fixed: Moved `PDFDocument(url:)` to a detached background task with `MainActor.run` callback.

- [x] **Sequential PDF text extraction** in `ExtractDocumentTextUseCase`
  - Fixed: Replaced sequential `for` loop with `withTaskGroup` for parallel extraction.

- [x] **No cancellation for thumbnail loading tasks** in `ThumbnailCache`
  - Fixed: Added `cancelAllInFlightTasks()` method that cancels and clears all in-flight thumbnail tasks.

- [x] **Main thread blocking in `ExportDocumentsUseCase`** during file copy
  - Reviewed: The bulk export runs after a modal `NSOpenPanel` which already blocks the run loop. File copies are sequential due to collision resolution. Added clarifying comment. No practical main-thread stall since the panel interaction dominates.

- [ ] **N+1 query pattern in `ManageLabelsUseCase`**
  - When managing labels for multiple documents, each document's labels are fetched individually. Consider batching.

- [x] **`PerformanceLogger` timing computed in Release builds**
  - Fixed: Gated `startTime` computation and `debugLogFilterTiming` call site with `#if DEBUG` in `LibraryCoordinator`. Gated `renderStartTime` and `.onAppear` logging in `LibrarySidebarView`.

---

## Priority 3 — Dead Code & Unused Imports

- [x] **Unused functions in `DocumentInspectorView`**: `openOriginalFile()` and `showOriginalFileInFinder()`
  - Fixed: Removed both unused methods.

- [x] **Unused `allDocuments` parameter** in `RootViewImportModifier`
  - Fixed: Removed unused parameter from `RootViewImportModifier`. `RootViewDialogsModifier` was a false positive — it uses `allDocuments` for `confirmDroppedLabelAssignment`.

- [x] **Unused `UniformTypeIdentifiers` import** in `LibrarySidebarView`
  - Fixed: Removed unused import.

---

## Priority 4 — Simplification & Consistency

- [x] **Repeated binding boilerplate in `LibraryCoordinator`**
  - Fixed: Extracted `optionalPresenceBinding(for:)` generic helper. `importSummaryBinding`, `exportSummaryBinding`, and `pendingDroppedLabelAssignmentBinding` now each delegate to this single implementation.

- [x] **Inconsistent `@StateObject` vs `@State` for observable objects**
  - Verified: `LibrarySessionController` uses `ObservableObject` with `@Published`, so `@StateObject` is correct. Other observable types use `@Observable` macro with `@State`. No inconsistency — false positive.

- [ ] **Inconsistent error handling patterns across use cases**
  - Some use cases throw errors, some return optionals, some return result types with failure arrays. Standardise on a single approach per error category.

- [x] **`DocumentRecord` date formatting repeated in multiple views**
  - Verified: Only two instances in `DocumentInspectorView` using the same format, and `DocumentListView` uses a different format for a different context. Not a real duplication — false positive.

---

## Priority 5 — Testing Gaps

- [x] **No unit tests for `ExportDocumentsUseCase`**
  - Fixed: Added 6 tests covering `suggestedFileName` — no labels, with labels, illegal characters, empty title fallback, sort order, and bulk export with real files.

- [ ] **No unit tests for `ExtractDocumentTextUseCase`**
  - Text extraction requires PDFs with actual text content; parallel backfill logic is integration-level. Deferred.

- [ ] **No UI tests for drag-and-drop workflows**
  - Drag-to-label assignment, drag-to-bin, and drag-to-Finder are untested. Requires XCUIAutomation drag APIs.

- [x] **No UI tests for search and filtering**
  - Fixed: Added unit tests for `SearchDocumentsUseCase` — fullText matching, empty query, case insensitivity. Existing UI test `testCommandFFocusesSearchFieldWhenLibraryIsOpen` covers the search field interaction.

- [ ] **No UI tests for multi-selection operations**
  - Bulk selection, bulk delete, and bulk export have no UI test coverage. Requires XCUIAutomation multi-click.

- [x] **No tests for `ManageLabelsUseCase`**
  - Fixed: Added tests for reorder, changeColor, changeIcon, empty name validation, and createLabel with color+icon. Existing tests already covered create, rename/merge, delete, assign, and remove.

---

## Priority 6 — Accessibility

- [x] **Missing accessibility labels on toolbar buttons**
  - Fixed: Added `.accessibilityLabel` to list/thumbnail view picker segments.

- [x] **Missing accessibility labels on document thumbnails**
  - Fixed: Added `.accessibilityLabel` with document title to thumbnail grid items.

- [x] **Missing accessibility hints on drag-and-drop targets**
  - Fixed: Added `.accessibilityHint` to label sidebar drop targets describing the drop action.

---

## Priority 7 — Findings from `docs/code-quality-analysis.md`

- [x] **Dead loop in `refreshWatchFolderMonitors`** (`LibraryCoordinator.swift:~651`)
  - Fixed: The teardown loop iterated over `allWatchFolders` using an ID set built from the same array, so it could never find a missing ID. Now iterates over `folderMonitorService.monitoredIDs` and stops any monitor whose folder ID is no longer in `allWatchFolders`. Added `monitoredIDs` accessor to `FolderMonitorService`.

- [x] **Duplicated `normalizedName` across 4 use cases**
  - Fixed: Extracted `StringNormalization.nonEmptyCollapsedWhitespace(_:emptyError:)` helper in `Shared/StringNormalization.swift`. All four use cases (`ManageLabelsUseCase`, `ManageLabelGroupsUseCase`, `ManageSmartFoldersUseCase`, `ManageWatchFoldersUseCase`) delegate to the shared helper.

- [x] **`static var` computed properties re-allocate JSONEncoder/JSONDecoder** (`DocumentLibraryService.swift:291-306`)
  - Fixed: Converted `prettyPrinted`/`libraryManifest` from computed `static var` to stored `static let` backed by closures. One shared instance per call site.

- [x] **`ManageLabelsUseCase.update` saves four times for one operation**
  - Fixed: Inlined mutations (normalize/merge, color, icon, group) and collapsed to a single `modelContext.save()` at the end.

- [x] **Regex patterns compiled on every call** (`ImportPDFDocumentsUseCase.swift:~290`)
  - Fixed: Hoisted the three content-disposition filename patterns into a `static let` array of `NSRegularExpression` values, compiled once at first access.

- [x] **`DocumentRecord.makeSamples` / `LabelTag.makeSamples` ship in Release binaries**
  - Fixed: Wrapped both factories (and the dependent `DocumentInspectorPreviewData` helper and corresponding `#Preview` blocks) in `#if DEBUG` so the preview/sample code is excluded from Release builds.

- [ ] **`Diagnostics` directory created but unused** (`DocumentLibraryService.swift:43`)
  - Kept: `docs/requirements.md:403` specifies `Diagnostics/import-log.json` as a planned layout. Keeping the directory reserved until the feature lands.
