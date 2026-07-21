# Analysis Log

This file is an append-only log of analyses (investigations, reviews, audits) performed on this repository. The newest entry is at the top. See [AGENTS.md](AGENTS.md#analysis-documentation) for the recording rules.

---

## Deep Security, Code Quality, and Performance Review

- **Date:** 2026-07-21
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Proceed with the analysis"

### Result

Read-only static review of the DocNest macOS app, including the import/export, library package, persistence, locking, OCR, watch-folder, preview, update, and coordinator paths. No app code was modified and no build or test command was run.

#### Findings

1. **High — Library metadata can cause reads and deletion outside its package.**
   - **Locations:** `DocNest/Infrastructure/Library/DocumentStorageService.swift:120-136`, `DocNest/Domain/UseCases/DeleteDocumentsUseCase.swift:31-51`, `DocNest/Domain/UseCases/ManageWatchFoldersUseCase.swift:234-245`
   - **Category:** Security, data safety
   - **Issue:** `storedFilePath` and `coverPhotoPath` are persisted strings from a user-selectable library package. They are appended directly to the library URL without rejecting absolute paths, `..` components, or symlink escapes. The resulting URLs are used for previews, Quick Look, export, OCR, and—most critically—best-effort `removeItem` calls. The integrity checker detects an out-of-library document path only after it has already used the same path for filesystem inspection.
   - **Impact:** A tampered, shared, or corrupted library database can make DocNest expose readable user files through document UI or delete files outside the library when the bin or a location cover photo is removed. The project is not sandboxed, making the affected scope the current user's writable files.
   - **Smallest practical remediation:** Centralize a throwing, confinement-checked resolver. Require a relative path under the intended root (`Originals/` for documents and `LocationPhotos/` for photos), reject absolute and traversal components, and compare standardized, symlink-resolved URLs against that root before every read, move, copy, or delete. Treat invalid persisted paths as integrity errors and never delete them.
   - **Suggested tests:** Open a library whose SQLite metadata contains `../outside.pdf`, an absolute path, and a symlink escape; assert preview/export/OCR reject the record and permanent deletion never touches an external sentinel file. Repeat for `coverPhotoPath`.

2. **High — The library lock is a check-then-write advisory file, so concurrent opens can both succeed.**
   - **Locations:** `DocNest/Infrastructure/Library/DocumentLibraryService.swift:529-566`
   - **Category:** Correctness, concurrency, data safety
   - **Issue:** `acquireLock` reads a lock and then overwrites it using atomic replacement. Two processes can both observe no lock (or a stale lock) before either writes, then both open the same SwiftData store. The heartbeat has the same overwrite semantics and provides no ownership verification.
   - **Impact:** Concurrent DocNest instances can write the same SQLite/SwiftData package, risking lost updates, migration/repair races, and database corruption. The five-second integrity-refresh work makes this race especially consequential immediately after open.
   - **Smallest practical remediation:** Use an OS-backed exclusive lock held for the library session (for example a file descriptor with `flock`/`fcntl` advisory locking) or an atomic exclusive-create protocol that verifies a unique owner token before refresh/release. Do not rely on PID/hostname JSON as the lock primitive.
   - **Suggested tests:** Launch two independent processes against the same temporary library at a synchronization barrier; assert exactly one can obtain a session. Test that a non-owner cannot refresh or remove an active owner's lock.

3. **High — Importing remote files and ZIP archives has no resource limits.**
   - **Locations:** `DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift:174-188`, `:343-352`, `:627-659`, `:662-801`; `DocNest/Infrastructure/OCR/OCRTextExtractionService.swift:316-343`
   - **Category:** Security, performance, reliability
   - **Issue:** The importer accepts arbitrary HTTP(S) downloads and extracts ZIPs with `ditto` before imposing a byte limit, entry limit, compression-ratio limit, extraction quota, or timeout. It then hashes every file and accepts arbitrary PDF page dimensions. Vision OCR renders each page at 300 DPI into an unbounded RGBA bitmap; a crafted or simply very large media box can request gigabytes of memory.
   - **Impact:** A URL or ZIP supplied through drag-and-drop, Services, or a watch folder can exhaust disk space, CPU, or memory and freeze/terminate the application. This is a practical local denial-of-service route for a document-management app that intentionally accepts untrusted files.
   - **Smallest practical remediation:** Set documented maximum download size, archive entry count, expanded-byte budget, and per-operation timeout; stop enumeration/extraction when a quota is exceeded. Validate PDF file/page limits before hashing or OCR, cap rendered pixel dimensions/total pixels, and report a clear per-file failure.
   - **Suggested tests:** Use a local URL protocol fixture with an oversized response, a highly compressed ZIP exceeding an expanded-size quota, a ZIP with excessive entries, and a PDF with an extreme media box; assert safe rejection and temporary-file cleanup.

4. **High — The self-updater permits path traversal before signature verification and does not require complete signer identity.**
   - **Locations:** `DocNest/App/AboutWindowController.swift:761-764`, `:820-829`, `:963-965`, `:999-1013`
   - **Category:** Security
   - **Issue:** The updater uses the remotely supplied release asset name as a path component without validating it, then unconditionally removes an existing destination before moving the download. An asset name containing traversal components can escape the freshly created update directory. Separately, signature identity checks are conditional: absent `Identifier`, absent expected team ID, or absent actual team ID all pass after a generic `codesign --verify`. The checked-in project uses manual ad-hoc signing settings, making a missing team identifier a realistic configuration.
   - **Impact:** A malicious/compromised release response can delete or overwrite user-writable files before the update payload is rejected. In deployments without a resolved team identifier, a validly signed app with the expected bundle identifier is not pinned to the publisher's signing identity.
   - **Smallest practical remediation:** Ignore remote filenames for filesystem paths or reduce them to a validated basename with a required `.dmg` extension; ensure the standardized destination remains under the generated temporary root. Pin a non-optional expected Developer ID team identifier (or certificate requirement) in shipped configuration, and fail closed when either identifier cannot be read or differs.
   - **Suggested tests:** Exercise `prepareInstaller` with `../sentinel.dmg`, an absolute asset name, and a nested asset name while placing sentinels outside the temporary root. Add signature-verification cases for missing signing identifier, missing expected team, and missing actual team; all must reject.

5. **Medium — Import coordination allows overlapping runs, defeating duplicate protection and corrupting progress state.**
   - **Locations:** `DocNest/App/LibraryCoordinator.swift:1243-1283`, `:1522-1546`; `DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift:218-224`, `:451-531`
   - **Category:** Concurrency, correctness
   - **Issue:** Starting a manual import replaces `activeImportTask` without cancelling or awaiting the prior task. Watch-folder callbacks create entirely untracked tasks. Each run snapshots known hashes before staging files, and `DocumentRecord.contentHash` has no uniqueness constraint, so concurrent runs can both stage and save the same PDF. The shared progress/summary state is also last-writer-wins.
   - **Impact:** Duplicate document records and duplicate stored files can be created after simultaneous drops, Services requests, or closely spaced watch events. Canceling an import may cancel only the most recently stored task while earlier work continues invisibly.
   - **Smallest practical remediation:** Serialize all imports per open library through one actor/queue, coalesce duplicate URLs or hashes before staging, and expose one cancellation-owned task. Enforce content-hash uniqueness transactionally at persistence level if SwiftData schema support allows it, otherwise recheck immediately before save within the serialized critical section.
   - **Suggested tests:** Start two imports of the same PDF concurrently and assert one stored file and one record. Trigger overlapping watch imports and then cancel; assert no untracked import continues and progress state remains coherent.

6. **Medium — Derived search/sidebar computation still executes on the main actor.**
   - **Locations:** `DocNest/App/LibraryCoordinator.swift:346-432`, `:464-535`
   - **Category:** Performance, code smell
   - **Issue:** The coordinator is `@MainActor`, and `Task { ... }` created in `recomputeFilteredDocuments` inherits that actor. `buildDerivedState` is synchronous, so marking it `nonisolated` does not move the work to another executor. The function repeatedly scans all document snapshots for filtering, smart-folder counts, label counts, and location counts—while its documentation claims the work happens off the main actor.
   - **Impact:** Typing in search, changing filters, or ingesting a large OCR-indexed library can block event handling and produce visible UI stalls. Cancellation checks cannot help while the main actor is occupied by the current computation.
   - **Smallest practical remediation:** Capture the existing `Sendable` snapshots and run `buildDerivedState` inside `Task.detached` (or a dedicated actor), then apply only the generation-checked result on `MainActor`. Profile/limit repeated full-library count calculations for large libraries.
   - **Suggested tests:** Add a performance regression test with a large snapshot set that asserts the main actor remains responsive while recomputation is pending, plus correctness tests that stale detached results never overwrite newer searches.

7. **Medium — OCR cancellation and failures can leave costly subprocesses running and silently lose extracted metadata.**
   - **Locations:** `DocNest/Infrastructure/OCR/OCRTextExtractionService.swift:160-213`, `DocNest/Domain/UseCases/ExtractDocumentTextUseCase.swift:37-68`
   - **Category:** Performance, reliability
   - **Issue:** OCRmyPDF is run in a detached task using `waitUntilExit()`, without cancellation propagation, a timeout, or streamed pipe draining. Cancelling the parent OCR operation cannot stop the subprocess; a verbose child can also fill the shared stdout/stderr pipe before exit. After all OCR work, `modelContext.save()` is wrapped in `try?`, so a persistence failure is hidden even though records were marked `ocrCompleted` in memory.
   - **Impact:** Cancelled OCR can keep CPU/disk-heavy child processes running and delay subsequent work. A failed final save can leave the user believing OCR completed while no extracted text is durable.
   - **Smallest practical remediation:** Use a cancellation handler that terminates and reaps the process, enforce a timeout, and drain stdout/stderr concurrently or redirect it safely. Return/propagate the model-save error and only show completion after a successful save (or restore state and surface a retryable error).
   - **Suggested tests:** Inject a long-running OCR process and assert cancellation terminates it; inject a model-context save failure and assert the result is an explicit failure without falsely reporting completed OCR.

8. **Low — User paths and external tool output are intentionally made public in logs.**
   - **Locations:** `DocNest/Infrastructure/Library/FolderMonitorService.swift:100-102`, `:317-319`; `DocNest/Infrastructure/OCR/OCRTextExtractionService.swift:193-210`
   - **Category:** Privacy
   - **Issue:** Watch-folder paths and OCRmyPDF stderr/error text are interpolated with `privacy: .public`. Those values can include user names, sensitive folder names, filenames, and external-tool diagnostics.
   - **Impact:** Private library/watch-folder information can be exposed in unified logging and diagnostics beyond the app's own UI.
   - **Smallest practical remediation:** Use default/private OSLog interpolation for paths and tool output; log only stable error codes/counts publicly. Make any detailed diagnostic collection an explicit, user-controlled export.
   - **Suggested tests:** Use OSLog test hooks or a logging abstraction to assert sensitive paths are not emitted as public fields.

#### Areas reviewed without further actionable findings

- Future library format validation now rejects formats newer than `currentFormatVersion` before opening the model container.
- The import pipeline hashes files incrementally rather than loading whole files into memory.
- Thumbnail loading has bounded in-flight work and cache-cost limits.
- SwiftData schema versions and migrations are explicitly enumerated through V6.

#### Residual risks and recommended verification

- Static review cannot validate PDFKit, Vision, `ditto`, and external OCRmyPDF behavior against malicious real-world documents; the quota and cancellation tests above should be followed by controlled runtime stress tests.
- Test after fixes using `make test` (required stable suite); additionally run targeted process/ZIP/PDF stress tests and `make test-ui` for import, cancellation, and update UI wiring where local macOS services permit.
- Overall readiness: **not ready for security-sensitive release** until findings 1–4 are resolved. Findings 5–7 should be addressed before claiming reliability or large-library performance readiness.

---

## Local Changes Commit Readiness

- **Date:** 2026-07-21
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Stop. First check the local changes and if they are ready to be committed"

### Result

The worktree is clean (`git status --short` produced no output), so there are no local changes to review, stage, or commit. The repository is on its locally configured default branch, `main` (`origin/main`).

Assessment: no pending change set exists; commit readiness does not apply.

---

## Normal Diff Review

- **Date:** 2026-06-30
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Normal review of the current uncommitted DocNest app diff under the updated AGENTS.md instructions. Review the diff, changed tests, and nearby affected code paths only. Do not edit files, compile, build, run the app, run tests, package artifacts, or execute verification commands. Prioritize correctness, regressions, missing tests, concurrency risks, data loss risks, UI behavior mismatches, native Settings behavior, `.searchable` toolbar focus behavior, `DocumentDateExtractor` behavior/thread safety, tests, and documentation. Report actionable findings only; if none, say no actionable findings and note residual verification."

### Result

No actionable findings were identified in the current app diff.

Reviewed changes:

- Native Settings migration: `DocNestApp` declares the SwiftUI `Settings` scene, and `AppSettingsController.show(_:)` preselects the pane before invoking AppKit's standard `showSettingsWindow:` action. The custom About window remains documented as intentionally custom because it hosts update workflow and live library statistics.
- Native toolbar search migration: `RootView` uses SwiftUI `.searchable` in the toolbar, removes the custom search field state token, and uses `SearchToolbarFocus` to bridge the existing search command to the native `NSSearchToolbarItem` on visible windows.
- Date extraction: `DocumentDateExtractor` uses `NSDataDetector` as the primary detector, requires an explicit four-digit year, preserves fixed-format fallbacks for detector gaps, creates `DateFormatter` instances per parse to avoid shared formatter thread-safety issues, and keeps earliest-in-reading-order behavior.
- Tests and requirements: focused date extraction tests cover ISO, English/German month names, numeric fallback recovery, earliest-date selection, no-date cases, and plausibility bounds. Requirements documentation reflects the native detector plus explicit fallback behavior.

Residual verification:

- `make test-unit` is still the main documented suite for unit/integration coverage and should remain green.
- `make test` should be rerun when the macOS UI test runner can initialize; the latest attempt failed before any UI test executed because LocalAuthentication reported "System authentication is running."

---

## Local Changes Commit Readiness

- **Date:** 2026-06-30
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "What is changed locally and should These changes be Committee"

### Result

The local worktree contains an in-progress native SDK cleanup and OCR date extraction refactor:

- Staged: `DocNest/Shared/SearchToolbarField.swift` is deleted and `DocNest/Shared/SearchToolbarFocus.swift` is added.
- Unstaged: the Xcode project file is updated to reference `SearchToolbarFocus.swift`; `RootView` switches from the custom search field to SwiftUI `.searchable`; `LibraryCoordinator` removes the search focus token; `AboutWindowController` removes the custom Settings window controller and opens the native SwiftUI Settings scene; `DocNestApp` declares the `Settings` scene; `DocumentDateExtractor` switches from hand-maintained regex/date formatters to `NSDataDetector` with numeric fallback; `DocNestTests` adds date extractor coverage.

Assessment:

- Do not commit the currently staged subset by itself. The staged delete/add is split from the unstaged project and call-site changes, so committing only staged files would leave the project in an inconsistent state.
- Do not treat the whole working tree as release-ready yet. Unit/integration tests passed in the prior review run, but UI tests could not initialize because macOS LocalAuthentication was already running.
- The changes are directionally coherent, but they should be committed only after staging the full related set together, running `git diff --check`, completing UI verification or documenting why it could not be run, and updating requirements documentation for changed date extraction behavior and native search/settings behavior if those are considered user-visible behavior changes.
- The previous complete app review also identified outstanding release-readiness defects unrelated to this local change set: future library manifest versions are accepted, nil-fallback OCR date updates are skipped, and watch-folder events can surface PDFs inside library packages.

Recommendation: not commit as-is. First fix the staging split, address or explicitly defer the outstanding defects, rerun canonical verification, and then commit the complete coherent change set.

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
