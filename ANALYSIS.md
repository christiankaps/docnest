# Analysis Log

This file is an append-only log of analyses (investigations, reviews, audits) performed on this repository. The newest entry is at the top. See [AGENTS.md](AGENTS.md#analysis-documentation) for the recording rules.

---

## Complete App Review

- **Date:** 2026-06-30
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Perform a complete app review of this repository as an independent senior reviewer.

Scope:
- Review the whole app, not just the latest diff.
- Focus on correctness, data safety, persistence, migrations, filesystem behavior, concurrency, UI workflows, macOS-native behavior, error handling, release readiness, and test coverage.
- Prioritize actionable defects over style opinions.
- Treat regressions, data loss risks, stale state, broken restore/open/import flows, unsafe delete behavior, and missing coverage as high priority.

Review process:
1. Read the project structure and key documentation first, especially AGENTS.md, docs/testing.md, requirements docs, and release notes if present.
2. Identify the main user workflows and trace them end to end:
   - app launch and library restore
   - create/open library
   - document import, cancellation, duplicate handling, and failed saves
   - document search/filter/selection
   - labels, label values, smart folders, and physical locations
   - document deletion/bin/restore/export
   - thumbnails, previews, OCR/text extraction, and background work
   - settings, updates, and release behavior
3. Inspect persistence and compatibility paths:
   - SwiftData models
   - migrations
   - released fixture coverage
   - partial writes and rollback behavior
   - stale IDs, orphaned records, missing files, and recovery paths
4. Inspect UI behavior:
   - sidebar interactions
   - dialogs and destructive confirmations
   - keyboard shortcuts
   - accessibility identifiers used by tests
   - macOS-native expectations
   - layout edge cases
5. Inspect tests:
   - whether risky workflows are covered
   - whether tests assert public behavior rather than implementation details
   - missing tests for high-risk behavior
   - flaky UI-test patterns or timing assumptions
6. Run or recommend the canonical verification commands from docs/testing.md if applicable.

Output format:
- Start with findings only.
- Order findings by severity: Critical, High, Medium, Low.
- For each finding include:
  - severity
  - affected file and line if available
  - what is wrong
  - why it matters
  - smallest practical fix
  - suggested test coverage
- If there are no actionable findings, say that clearly.
- After findings, include:
  - open questions or assumptions
  - residual risks
  - recommended verification commands
  - a short overall readiness assessment

Do not make code changes unless explicitly asked. Do not include broad praise or style-only commentary unless it affects correctness or maintainability."

### Result

#### Findings

1. **High — future library formats are accepted and opened with the current schema.**
   - **Affected files:** `DocNest/Infrastructure/Library/DocumentLibraryService.swift:308`, `DocNest/Infrastructure/Library/DocumentLibraryService.swift:330`
   - **What is wrong:** `migrateLibraryIfNeeded` returns `.none` whenever `manifest.formatVersion >= currentFormatVersion`, and `validateLibrary` only decodes the manifest without rejecting future versions. A library created by a newer DocNest can proceed into `openModelContainer(for:)` with the older app's current SwiftData schema and repair/integrity code.
   - **Why it matters:** This is a compatibility and data-safety issue. An older app should not open and potentially write integrity/repair artifacts or migrated metadata into an unknown newer package format.
   - **Smallest practical fix:** Add a validation error for `manifest.formatVersion > currentFormatVersion` before opening the model container or running repair/migration. Surface a user-facing "library was created by a newer version" error and leave the package unchanged.
   - **Suggested test coverage:** Add unit tests that create a valid package manifest with `formatVersion = currentFormatVersion + 1` and assert restore/open fails before `openModelContainer`, migration, lock acquisition, and integrity artifact writes.

2. **Medium — OCR date extraction skips documents whose fallback date is nil.**
   - **Affected files:** `DocNest/Domain/UseCases/ExtractDocumentTextUseCase.swift:15`, `DocNest/App/LibraryCoordinator.swift:1349`
   - **What is wrong:** `OCRDateUpdatePolicy.shouldUpdateDate` uses `guard let fallbackDate = fallbackDatesByDocumentID[...]`, so a dictionary entry whose intended fallback is `nil` is treated the same as "no update allowed." The queued-OCR path repeats the same issue with `if let fallback = dateFallbacksByDocumentID[...]`, so nil fallbacks are dropped before queueing.
   - **Why it matters:** Imported PDFs without a filesystem creation date will keep `documentDate == nil` even when OCR later finds an invoice or contract date. That breaks date metadata for a real import path and is not covered by the current OCR date policy tests.
   - **Smallest practical fix:** Track key presence separately from optional value, e.g. `guard fallbackDatesByDocumentID.keys.contains(document.persistentModelID) else { return false }`, then compare `document.documentDate` to the optional fallback. Preserve nil-valued entries when queueing.
   - **Suggested test coverage:** Add tests for immediate and queued OCR backfill where the imported document's fallback date is nil and OCR text contains a valid date; assert the extracted date is persisted.

3. **Medium — watch-folder incremental events can surface PDFs from inside a watched library package.**
   - **Affected files:** `DocNest/Domain/UseCases/ManageWatchFoldersUseCase.swift:84`, `DocNest/Infrastructure/Library/FolderMonitorService.swift:395`
   - **What is wrong:** Watch-folder validation rejects a folder inside the active library, but it does not reject or special-case a folder that contains the active library as a descendant. Full scans use `enumeratePDFs(... .skipsPackageDescendants)`, but incremental events in `applyFileEvents` accept any descendant `.pdf` path and do not skip package descendants or the active library path.
   - **Why it matters:** If a user watches a parent folder that contains `My Library.docnestlibrary`, every normal import can create FSEvents for `Originals/...pdf`. The monitor can pass those internal PDFs back into the import pipeline, which then rejects them as self-import failures and can show noisy or misleading import errors.
   - **Smallest practical fix:** Either reject watch folders that are ancestors of the active library package, or pass the active library URL into event filtering and ignore paths contained in that package. Also align incremental event filtering with the full-scan `.skipsPackageDescendants` behavior.
   - **Suggested test coverage:** Add a `FolderMonitorService.applyFileEvents` test where `folderPath` is a parent of a `.docnestlibrary` package and the event path is `...docnestlibrary/Originals/foo.pdf`; assert no URL is reported and no snapshot is retained. Add a validation test if choosing ancestor rejection.

#### Open Questions / Assumptions

- The review covered the current working tree, which already had uncommitted app/test changes. Those changes were not modified.
- I did not manually launch the app UI. The current UI automation runner could not initialize because macOS reported `System authentication is running`.
- The recent `NavigationSplitView` / `.searchable` changes still need runtime UI verification for sidebar non-toggleability, Cmd-F focus behavior, inspector presentation, and toolbar layout.

#### Verification Performed

- `make test` was run. The app built successfully and `DocNestTests` passed: 193 tests executed, 1 skipped, 0 failures.
- The same `make test` run failed before executing UI tests because `DocNestUITests-Runner` could not initialize UI testing: `com.apple.LocalAuthentication Code=-4 "System authentication is running."`
- `make test-ui` was retried and failed the same way before any UI test executed.

#### Recommended Verification Commands

- `make test-ui` after the macOS LocalAuthentication state clears.
- `make test` after fixing the findings.
- `make analyze` before release if the current UI/layout changes are retained.

#### Overall Readiness Assessment

Not release-ready until the future-format guard and nil-fallback OCR date issue are fixed and UI tests can run. Unit/integration coverage is strong for many persistence and filesystem paths, but the current UI target is unverified in this environment.

---

## Native SDK Preference — App Audit

- **Date:** 2026-06-15
- **AI model:** Claude Opus 4.8 (`claude-opus-4-8`)
- **Prompt:** "Analyze the whole app for the native SDK preference rule."

### Result

Audit of the codebase against the **Native SDK Preference** rule (AGENTS.md): custom implementations where an Apple framework / Swift native solution exists.

#### 🔴 Clear opportunities (native exists, custom code used without a documented reason)

**1. Date parsing — `DocNest/Infrastructure/OCR/DocumentDateExtractor.swift`**
~130 lines of hand-written `NSRegularExpression` patterns + 17 `DateFormatter` permutations for EN/DE dates. Apple's native solution is **`NSDataDetector`** (`.date` checking type), which detects dates in natural-language text across locales and returns a `Date` directly. The custom approach also has latent bugs the native one avoids (e.g. `MM/dd` vs `dd.MM` ambiguity; the `formatter.locale = nil` line at `:73` is a no-op). Strongest candidate — a pure data-detection task the native API directly covers.

**2. Settings & About windows — `DocNest/App/AboutWindowController.swift`**
Three hand-built `NSWindowController` subclasses (`About`, `Help`, `Settings`) wired through `CommandGroup(replacing: .appSettings)` in `DocNestApp.swift:344`. Native equivalents:
- Settings → SwiftUI **`Settings { … }`** scene (auto-wires ⌘, menu item, standard window).
- About → **`NSApplication.orderFrontStandardAboutPanel`** or a `Window` scene.

The Help window is reasonable as custom; Settings/About are the textbook native-scene cases.

**3. Search field — `DocNest/Shared/SearchToolbarField.swift`**
A full `NSSearchField` `NSViewRepresentable` bridge. SwiftUI's native **`.searchable`** modifier covers this. *Caveat:* it's placed in a custom `.principal` toolbar slot with a programmatic focus token, which `.searchable` doesn't map onto cleanly — "native exists but may not fit 100%", so raise before migrating.

#### 🟡 Documented "native didn't fit" cases (rule says *ask* — already justified in comments)

**4. Drag-to-Finder — `DocNest/Features/Documents/DocumentDragSupport.swift:84`**
Custom `NSDraggingSource` bridge. The comment explicitly states *"SwiftUI's standard file drag support did not fit DocNest's mixed internal and external drag contract."* This is exactly the rule's escape hatch, and it's documented. Native alternatives (`.draggable`, `NSItemProvider` file promises) genuinely struggle with deferred temp-file materialization — reasonable to keep.

**5. Resizable column list — `DocNest/Features/Documents/DocumentListView.swift:1177`**
`ResizableColumnHeader` + manual `DragGesture` width math + `NSCursor` management (`ResizeHandleCursorState.swift`). SwiftUI's native **`Table`** (macOS 12+) gives resizable/reorderable columns for free. Likely won't fit 100% (thumbnail view mode, custom label-chip cells, the drag handle) — an *ask-the-user* case, currently undocumented as a deliberate choice.

#### 🟢 Already compliant (good native usage)

- **OCR**: `Vision` (`VNRecognizeTextRequest`) + `PDFKit` + `CoreGraphics` rendering — all native. OCRmyPDF is an *optional* external tool with Vision fallback (intentional design, not a reinvention).
- **Folder monitoring** (`FolderMonitorService.swift`): `FSEvents` is the correct native API for recursive folder watching (not a custom poller).
- **Search matching** (`SearchDocumentsUseCase.swift:111`): native `String.range(of:options:[.caseInsensitive,.diacriticInsensitive])`.
- **Layout**: `NavigationSplitView` + `.inspector` (merged from PR #5) replaced the old hand-rolled `HStack`.
- `StringNormalization`, `DeferredSelectionState` — trivial domain logic with no single native equivalent.

### Recommendation

Act without hesitation on **#1 (DocumentDateExtractor → NSDataDetector)** — a clean, well-tested native replacement for a large, bug-prone custom implementation. **#2 (Settings/About scenes)** is also a safe, idiomatic win. **#3–#5** are genuine "native exists but may not fit 100%" cases that the rule says to raise with the user before changing.
