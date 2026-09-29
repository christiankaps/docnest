# Analysis Log

This file is an append-only log of analyses (investigations, reviews, audits) performed on this repository. The newest entry is at the top. See [AGENTS.md](AGENTS.md#analysis-documentation) for the recording rules.

---

## Overall Project Implementation Status

- **Date:** 2026-09-29
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Nein. Wie ist insgesamt der Projektstatus?"

### Result

DocNest is feature-complete for its documented v1/MVP scope in source and requirements documentation, but it is **not ready to be represented as production-release-ready**. The working tree is clean on `main`. The last substantive application changes landed on 2026-07-21, and the most recent commit (2026-09-07) records a security/design review rather than a remediation. No build, test, static-analysis, UI verification, release-artifact verification, or network-based release check was run for this read-only assessment; current green build/test and GitHub-release status are therefore unknown.

#### Implementation coverage

- The documented v1 workflows are present: local library creation/opening, PDF import from files/folders/URLs/services/Dock/watch folders, duplicate detection, list/thumbnail display, PDF/Quick Look preview, labels/groups/smart folders, filtering and full-text search, export/share/Finder access, OCR, migrations, and package-integrity checks.
- The codebase has a coherent native-macOS architecture: SwiftUI/AppKit for UI integration, SwiftData with a versioned migration chain through schema V6, and Apple frameworks rather than third-party dependencies. The repository has 49 production Swift files and a consolidated unit/integration test target.
- The recent implementation history shows meaningful hardening work for import, library, OCR, update, and native-menu behavior. The required test command is documented as `make test`; warnings are configured as errors for build, test, analysis, archive, and packaging commands.

#### Release blockers and material risks

1. **Automatic updates and public distribution are not release-ready.** The 2026-09-07 security review found that the release workflow produces ad-hoc-signed artifacts without a configured trusted update team, Developer ID signing, notarization, or stapling. The updater fails closed when that team is absent, so workflow-built releases cannot use the advertised automatic-install path. This is the primary release blocker.
2. **Library integrity has unresolved high-risk lifecycle paths.** The same review found that background import/OCR/integrity work can outlive library close/switch and continue accessing the old library after its exclusive lock has been released. Permanent deletion can also report success after metadata is deleted even when removal of the stored PDF fails, leaving an unmanaged sensitive-file orphan.
3. **Untrusted-import containment is incomplete.** The remote-download and ZIP limits do not yet constrain all temporary disk, entry-count, path-depth, inode, CPU, or elapsed-time costs. This leaves a practical local denial-of-service risk from malicious or extreme inputs.
4. **Documentation has drifted from the implementation.** `docs/requirements.md` describes watch folders as `DispatchSource`/file-descriptor based, while the active implementation uses `FSEventStream`. The same UI status can report `monitoring` solely because the folder exists and is enabled, even if `FSEventStreamCreate` or `FSEventStreamStart` failed; it also is not recomputed when a monitored path later vanishes. The user-visible contract and implementation need reconciliation.

#### Engineering status

- No current uncommitted work or obvious repository-wide TODO/FIXME backlog was found in production sources. The main structural maintenance concern remains the large `LibraryCoordinator`, which combines UI state, filtering, import/export, OCR, and watch-folder orchestration.
- The repository has good process documentation and a non-optional code-change gate, but this assessment cannot establish current test health because it intentionally did not execute verification commands.
- GitHub/origin freshness and latest published release could not be checked in this environment because the configured SSH remote hostname could not be resolved. This is an environment/network limitation, not evidence that the remote is unhealthy.

#### Recommended next status

Treat the project as **MVP-complete, internally usable, and in a release-hardening phase**. Before the next public release, prioritize: (1) signed/notarized release pipeline plus updater-trust verification, (2) library-task shutdown/lock ownership and deletion atomicity, (3) bounded streaming/archive import defenses, (4) correction and testing of watch-folder state/reporting, then (5) a clean `make test`, static analysis, and release-artifact validation on a network-capable machine.

---

## Complete App Implementation, Security, and Design Review

- **Date:** 2026-09-07
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Do a complete review of the App. Do not question the overall app idea but check for real implementation issues without challanging the app concept. Check for security vulnerabilities and design flaws"

### Result

Static review of the current app implementation, persistence and package format, import/export/OCR pipelines, watch-folder monitoring, update mechanism, UI state architecture, tests, and build/release configuration. The product concept was treated as fixed and was not evaluated. No application code was changed, and no build, test, analyzer, live UI, malicious-file execution, signing, or notarization command was run as part of this read-only audit.

The code has several strong controls already in place: persisted document and location-photo paths are confined to managed library roots; libraries use an OS-backed exclusive file lock; imported source size, archive expansion, and OCR page rendering have explicit limits; updater filenames are not trusted as paths; updater signature checks fail closed when signer identity is absent; subprocess arguments are passed without shell interpolation except in the separately escaped installer script; and no committed credential or private key was found by the repository scan.

#### Findings

1. **High — The release pipeline does not produce an update-verifiable, notarized distribution.**
   - **Locations:** `project.yml:6-17`; `DocNest.xcodeproj/project.pbxproj:587-593,732-737`; `.github/workflows/release.yml:38-92`; `DocNest/App/AboutWindowController.swift:754-770,968-1024`
   - **Issue:** Both generated build configurations use manual ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) with an empty development team. The release workflow does not override those settings, inject `DocNestUpdateTeamIdentifier`, sign with a Developer ID certificate, notarize the app/DMG, or staple a notarization ticket. The updater correctly refuses installation without a configured trusted team, so an artifact produced by this workflow cannot pass its own automatic-update trust policy. The uploaded DMG also lacks a normal Developer ID/notarization distribution chain.
   - **Impact:** The advertised Install Update path is nonfunctional for workflow-built releases, and users receive weaker provenance/Gatekeeper behavior than the updater design assumes. Treating ad-hoc artifacts as public releases also makes a later signing transition harder to validate safely.
   - **Recommendation:** Sign release archives with a protected Developer ID Application identity, set the trusted team identifier in the built Info.plist, notarize and staple the app/DMG, and fail the workflow unless `codesign --verify --strict`, designated-requirement/team checks, `spctl --assess`, and stapler validation all pass. Keep ad-hoc signing only for local development.
   - **Tests/gates:** Add a release-artifact verification step that reads the actual built app's team identifier and updater configuration, then rejects an absent/mismatched identity or unstapled artifact.

2. **High — “Permanent” deletion can silently retain the PDF after deleting its only metadata record.**
   - **Locations:** `DocNest/Domain/UseCases/DeleteDocumentsUseCase.swift:31-51`; `DocNest/Infrastructure/Library/DocumentStorageService.swift:126-128`; `DocNestTests/DocNestTests.swift:2602-2635`
   - **Issue:** Hard deletion first deletes the SwiftData records and saves. It then removes each stored file through a non-throwing helper that suppresses every filesystem error. A permissions error, open-file error, volume failure, or transient I/O error therefore leaves the PDF in `Originals/` while the app reports success and has discarded the record needed to locate it. The integrity checker only walks records, so it will not report this orphan.
   - **Impact:** Sensitive document content can remain on disk after the user explicitly chose permanent deletion. The orphan is also no longer manageable from the app, producing package bloat and a privacy/data-retention defect.
   - **Recommendation:** Make file removal report failures and make the workflow crash-robust. Prefer moving files atomically to a library-owned quarantine/staging directory, saving metadata deletion, and then removing the staged files; restore them if the save fails. If final removal fails, retain recoverable metadata or record a visible cleanup issue instead of claiming success.
   - **Tests:** Inject a failing filesystem operation and assert that the document remains recoverable and the user receives an error; add orphan detection/repair coverage.

3. **High — Closing or switching libraries can release the exclusive lock while detached work still reads or writes the old library.**
   - **Locations:** `DocNest/App/DocNestApp.swift:582-596,636-669`; `DocNest/Infrastructure/Library/DocumentLibraryService.swift:419-443,474-526`; `DocNest/App/LibraryCoordinator.swift:144-155,1230-1298,1318-1347,1454-1460`; `DocNest/Domain/UseCases/ExtractDocumentTextUseCase.swift:37-68`; `DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift:659-669`
   - **Issue:** Session close cancels the integrity wrapper and immediately releases the library lock. The integrity operation itself is an unstructured `Task.detached` with no cancellation handler/check and can still open a second model container, repair metadata, save, and write diagnostics. Import metadata and OCR also use unstructured detached tasks whose cancellation is not propagated from the owning UI task. Coordinator teardown requests cancellation but does not await quiescence before the session releases the lock.
   - **Impact:** After a user closes/switches a library, background work can continue touching it without ownership of the lock. Another DocNest process can acquire the lock meanwhile, defeating the lock's data-integrity guarantee and allowing cross-session writes/races. The OCR Cancel button can also appear to finish while a current detached extraction continues, potentially for the five-minute external-tool timeout.
   - **Recommendation:** Give the library session ownership of all library-scoped tasks. Use structured child tasks where possible; otherwise explicitly cancel and await detached tasks. Do not release the file lock or security scope until all mutating/reading maintenance, import, and OCR tasks have stopped. Avoid opening a second independent `ModelContainer` for repair while the live one is active; perform maintenance through a coordinated context/container.
   - **Tests:** Block integrity repair/OCR/import at deterministic barriers, close or switch the library, and assert no post-release filesystem/database write occurs and a second process cannot acquire the lock until work is quiescent.

4. **High — Import resource limits do not fully contain untrusted downloads and ZIP archives.**
   - **Locations:** `DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift:108-123,358-376,698-723,762-860`
   - **Issue:** Remote content is fully downloaded by `URLSession.download` before the 512 MB check, so the limit does not bound network or temporary-disk consumption. ZIP extraction has an expanded-byte check but no entry-count, path-depth, per-file, or total-operation time limit. Its polling repeatedly walks the growing extraction tree, which becomes increasingly expensive, and extraction can continue while that full scan runs. A very large number of tiny/empty entries can remain below the byte limit while exhausting memory, inodes, CPU, and the `results` array. Non-cancellation resolver errors, including safety-limit errors, are swallowed and converted into an empty result, obscuring the cause from the user.
   - **Impact:** A pasted/opened URL or ZIP can cause local denial of service, excessive disk/inode use, or a long UI workflow despite the documented limits. Watch-folder and folder enumeration similarly materialize every PDF URL before import.
   - **Recommendation:** Stream downloads with a delegate that cancels as soon as received bytes exceed the limit and validate expected length/status/content type early. Preflight archives with a bounded entry listing, enforce entry count/path depth/per-entry and total expanded quotas, add a wall-clock timeout, and avoid repeated whole-tree scans. Stream/batch directory candidates rather than accumulating an unbounded array. Preserve and display validation errors.
   - **Tests:** Cover a chunked oversized response, unknown-length response, excessive-entry ZIP, deep-path ZIP, expansion overshoot, timeout, and clear error reporting/temporary cleanup.

5. **Medium — Files are accepted as documents by extension even when PDFKit cannot parse them.**
   - **Locations:** `DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift:256-283,659-679,877-889`
   - **Issue:** A `.pdf` extension is sufficient to enter the pipeline. `PDFDocument(url:)` is optional, but a `nil` result is converted into `pageCount = 0` and still committed as a normal document. Corrupt, non-PDF, or unsupported/encrypted inputs therefore become persistent records with unusable previews and OCR rather than per-file failures.
   - **Impact:** The library can accumulate invalid records that look successfully imported, weakening metadata integrity and confusing duplicate, preview, OCR, and export behavior.
   - **Recommendation:** Require PDFKit to open the file and validate a usable page count before copying/committing it. Define explicit behavior for locked/encrypted and zero-page PDFs and report those cases in the import summary.
   - **Tests:** Add renamed-non-PDF, truncated/corrupt PDF, encrypted PDF, and zero-page fixtures and assert the documented outcome.

6. **Medium — Two expensive “background” UI computations still execute on the main actor.**
   - **Locations:** `DocNest/Features/Documents/DocumentListView.swift:79-121`; `DocNest/App/LibraryCoordinator.swift:691-753`
   - **Issue:** `DocumentListView.recomputeSortedDocuments` and label-value statistics use `Task { ... }` from main-actor-isolated UI/coordinator code. Such tasks inherit the actor context, so the synchronous sort, statistics passes, dictionary construction, and reductions run on the main actor. The later `MainActor.run` does not move the preceding work off it. This contradicts the code's responsiveness intent and the requirements for non-blocking selection/statistics.
   - **Impact:** Large libraries or value sets can cause typing, sorting, selection, and scrolling stalls. Cancellation cannot interrupt the synchronous sort/reductions until they complete.
   - **Recommendation:** Snapshot only Sendable value data on the main actor, perform pure sorting/statistics in `Task.detached` (or a dedicated actor), include periodic cancellation checks, and apply results on the main actor behind the existing generation guards.
   - **Tests/verification:** Add large synthetic snapshot performance/cancellation tests and profile search, sort, selection, and label statistics with Time Profiler and hangs instrumentation.

7. **Medium — Custom Edit-menu replacement removes standard macOS editing commands from text-entry workflows.**
   - **Locations:** `DocNest/App/DocNestApp.swift:207-238`; text-entry surfaces throughout `DocumentListView`, `DocumentInspectorView`, and label/location editors
   - **Issue:** Replacing the entire `.pasteboard` group with only Paste removes the standard Cut and Copy menu items. Replacing `.textEditing` with only Find, Assign Labels, and Select All removes system-provided editing/writing commands from the menu even though the app contains editable title, label, location, numeric-value, and date fields. This partially reintroduces the native-menu defect that the most recent UI remediation intended to remove.
   - **Impact:** Expected menu discoverability, responder-chain behavior, Services/writing tools, keyboard accessibility, and assistive automation can be impaired in focused text fields.
   - **Recommendation:** Preserve the standard pasteboard and text-editing groups. Add app-specific Find/Assign/Select commands in an additive command group or route commands conditionally through the focused responder without replacing unrelated native actions.
   - **Verification:** Check Cut/Copy/Paste, Undo/Redo, Select All, spelling/writing tools, Services, and VoiceOver in every editable field.

8. **Medium — The app has no App Sandbox boundary despite routinely parsing untrusted files and invoking external tools.**
   - **Locations:** `project.yml:6-17,24-44`; `DocNest.xcodeproj/project.pbxproj` (no app-sandbox entitlement/settings); `DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift`; `DocNest/Infrastructure/OCR/OCRTextExtractionService.swift:157-281`
   - **Issue:** Hardened Runtime is enabled, but the app target has no App Sandbox entitlement or entitlements file. It accepts PDFs/ZIPs/URLs and watch-folder content, exercises PDFKit/Vision/system archive parsing, and can launch locally discovered OCR executables. Any exploitable parser or dependency defect therefore executes with all filesystem/network access granted to the user's process rather than access limited to selected libraries/watch folders and required network destinations.
   - **Impact:** This is a defense-in-depth gap: a malicious document or compromised local OCR tool has a much larger blast radius. It is not evidence of a currently exploitable parser bug, but it materially worsens the outcome of one.
   - **Recommendation:** Evaluate enabling App Sandbox with user-selected read/write access, persistent security-scoped bookmarks for libraries/watch folders, and outbound network access only where required. If sandboxing is intentionally deferred, document the threat model and avoid searching arbitrary inherited `PATH` entries for OCR executables; require an explicit trusted executable choice or fixed trusted locations.

9. **Low — Diagnostics and some logs can disclose document/library metadata.**
   - **Locations:** `DocNest/Infrastructure/Library/DocumentLibraryService.swift:446-470,489-519`; `DocNest/App/DocNestApp.swift:667`; `DocNest/Domain/UseCases/ExtractDocumentTextUseCase.swift:48`; `DocNest/Domain/UseCases/ExportDocumentsUseCase.swift:131,180`
   - **Issue:** The diagnostics file stored inside every portable library includes the user's absolute library path and document titles in repair messages. Several logs interpolate document titles, and library-maintenance errors are explicitly marked public even though filesystem errors can include absolute paths.
   - **Impact:** Sharing or backing up a library also shares local username/path and document-title metadata; unified logs can retain sensitive names and paths useful for support but unnecessary for normal operation.
   - **Recommendation:** Store a package-relative or redacted path in diagnostics, use document UUIDs or private log interpolation for titles, and mark filesystem error text private unless the user explicitly exports a diagnostic report with informed consent.

10. **Low — CI and release builds bypass the repository's documented warning/static-analysis policy.**
    - **Locations:** `Makefile:8-13,40-68`; `docs/testing.md:12-46`; `.github/workflows/ci.yml:23-52`; `.github/workflows/release.yml:38-49`
    - **Issue:** Local Make targets pass Swift/GCC/Clang warnings-as-errors, but CI invokes raw `xcodebuild` without those flags. The release workflow also skips the analyzer and the explicit release optimization/warning flags used by `make archive`.
    - **Impact:** Code that the documented local gate rejects can build, test, and ship remotely. This is especially risky in a codebase using concurrency, filesystem APIs, Core Foundation callbacks, and subprocesses where compiler diagnostics are valuable.
    - **Recommendation:** Make CI call the canonical Make targets or pass the identical flags, run `make analyze` before packaging, and fail releases unless required unit tests and artifact verification have passed for the exact release commit.

#### Architectural observations and residual risks

- The domain/use-case/infrastructure separation is sound, but several UI/controller files are very large (`DocumentListView`, `DocumentInspectorView`, `LibrarySidebarView`, `LibraryCoordinator`, and `AboutWindowController`). This is maintainability risk rather than a standalone defect; future changes should extract cohesive behavior only when backed by tests, not perform a wholesale rewrite.
- Current tests cover many important success, cancellation, migration, path-confinement, locking, label-value, export, and updater-signature paths. The main gaps align with the findings above: injected filesystem failures, close/switch task quiescence, adversarial archive/download limits, invalid PDF parsing, release artifact identity, and large-dataset main-thread behavior.
- No direct credential exposure, path-traversal escape from managed document/photo storage, shell argument injection in ordinary subprocess calls, updater signer-bypass, or concurrent-library-open bypass was identified in the reviewed current source. This does not substitute for dynamic fuzzing of PDF/ZIP inputs, runtime race testing, accessibility testing, or an independent signed-artifact penetration review.

#### Recommended remediation order

1. Make hard deletion recoverable and make session shutdown wait for all library-scoped work before releasing the lock.
2. Establish Developer ID signing, trusted-team configuration, notarization/stapling, and release-artifact verification before relying on automatic updates.
3. Finish import download/archive quotas and reject unparseable PDFs.
4. Move sorting/statistics off the main actor and restore standard Edit-menu groups.
5. Decide and document the sandbox threat model, then minimize diagnostics/log disclosure and align CI with the documented gates.

---

## Release Compiler Settings and Static Analysis Check

- **Date:** 2026-07-22
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Check Compiler Settings: Is the release build with all optimizations enabled? Is static code check done?"

### Result

**Release optimization:** Yes, the Release profile is fully optimized for normal production use. `make release-build` completed successfully with compiler warnings treated as errors. The effective configuration in `DocNest.xcodeproj/project.pbxproj` and the release build command enables:

- Swift `-O` optimization and whole-module compilation;
- LLVM link-time optimization;
- dead-code stripping, copy-phase stripping, and installed-product stripping;
- release dSYMs, no testability, and disabled NS assertions;
- fast Metal math; and
- C/Objective-C size optimization (`GCC_OPTIMIZATION_LEVEL=s`).

The profile deliberately does not use Swift `-Ounchecked`. That mode removes runtime safety checks and is not an appropriate default for a document-management app; `-O` is the correct safe production optimization level.

**Static analysis:** Yes, `make analyze` was run on 2026-07-22 and completed with `** ANALYZE SUCCEEDED **`. The command treats Swift, GCC, and Clang warnings as errors. Xcode emitted only environmental/tool metadata notices (for example, no AppIntents dependency), not analyzer findings or compiler diagnostics.

#### Process finding

The GitHub release workflow (`.github/workflows/release.yml`) archives the Release configuration but does **not** run `make analyze` and does **not** explicitly apply the repository's warning-as-error settings. Thus, static analysis is currently a manual release gate rather than CI-enforced, and a remote archive could accept compiler warnings that local Make targets reject.

**Recommendation:** Add an analysis step before archiving and pass `SWIFT_TREAT_WARNINGS_AS_ERRORS=YES`, `GCC_TREAT_WARNINGS_AS_ERRORS=YES`, and `CLANG_TREAT_WARNINGS_AS_ERRORS=YES` to the archive command (or call the documented Make target). This is a release-workflow change and should be implemented and verified separately.

---

## UI/UX and macOS-Native Design Review

- **Date:** 2026-07-21
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Check the UI/UX. Is it intuitive? Can it be Sinologie by using macOS native Funktionalität and APIs?"

### Result

Static UI/UX review of the current SwiftUI/AppKit implementation. No product code, build, live usability session, or assistive-technology test was performed.

**Overall assessment:** The primary workflow is intuitive: choose or create a library, import documents, find them through search/sidebar filters, inspect details, and use Quick Look. The app already uses the right macOS foundations in many high-value places: `NavigationSplitView`, `ContentUnavailableView`, native file importing, drag and drop, toolbar search, confirmation dialogs, a SwiftUI `Settings` scene, and Quick Look. The main opportunity is simplification by allowing macOS to provide more of the command, selection, and presentation behavior.

#### Findings and recommendations

1. **High — The app removes useful, expected macOS menu functionality.**
   - **Locations:** `DocNest/App/DocNestApp.swift:63-207`, `:274-287`
   - **Issue:** The app repeatedly edits the live `NSMenu` tree by English/German menu titles for five seconds after activation, while `SuppressUnusedMenuCommands` replaces Services, sidebar, toolbar, window arrangement/size, text formatting, undo/redo, and related command groups. This is brittle across macOS versions and localizations, and removes familiar features such as spelling, Dictation, Emoji & Symbols, Services, and standard toolbar/sidebar controls.
   - **Why it matters:** A document-management app benefits from system writing and accessibility tools. Removing them makes the app feel less native and makes basic actions harder to discover or automate.
   - **Recommendation:** Remove the timer-based `NSMenu` surgery and title matching. Use SwiftUI `Commands` only to replace actions that DocNest genuinely implements differently; retain standard macOS menus and controls where the app supports their behavior. Keep only a narrowly scoped, documented suppression when a command is genuinely unsafe or unsupported.

2. **Medium — The quick-label picker is a custom modal-like overlay where a native anchored control would be clearer.**
   - **Locations:** `DocNest/App/RootView.swift:225-239`; `DocNest/Features/Documents/QuickLabelPickerView.swift`
   - **Issue:** A nearly transparent full-window tap target and a manually positioned panel simulate dismissal and placement. The picker is not visibly anchored to the command that opens it.
   - **Why it matters:** A macOS `Popover`, `Menu`, or AppKit `NSMenu` communicates context, manages focus and dismissal consistently, and has better default accessibility/keyboard behavior.
   - **Recommendation:** Present the picker from an explicit toolbar or selection action using an anchored `.popover`; use a `Menu`/`NSMenu` if type-ahead search is not required. Preserve the current searchable multi-label workflow inside the popover when search is needed.

3. **Medium — The custom sidebar and list duplicate native collection behavior.**
   - **Locations:** `DocNest/Features/Library/LibrarySidebarView.swift`; `DocNest/Features/Documents/DocumentListView.swift`
   - **Issue:** The sidebar is a custom `ScrollView` of plain buttons, and list mode hand-builds selection, columns, sorting, and resizing. This gives the app visual control, but duplicates standard sidebar/table behavior and increases the keyboard, focus, selection, accessibility, and maintenance surface.
   - **Recommendation:** Evaluate `List(selection:)` with native sidebar sections/disclosure groups for the library navigation. For the conventional list view, evaluate SwiftUI `Table` for native column sorting, resizing, selection, and context menus; retain the custom grid/grouped view where its richer layout is genuinely needed. This should be an incremental migration, not a wholesale visual rewrite, because label grouping and drag/reorder workflows are product-specific.

4. **Low — One confirmation action is incorrectly styled as destructive.**
   - **Location:** `DocNest/App/RootView.swift:453-455`
   - **Issue:** “Assign Label” uses `role: .destructive`.
   - **Why it matters:** macOS uses destructive styling to signal irreversible or harmful actions, so this weakens the meaning of red confirmation actions.
   - **Recommendation:** Remove the destructive role; retain it only for actual deletion or permanent removal.

5. **Low — Import language understates supported input types.**
   - **Locations:** `DocNest/App/RootView.swift:269-275`; `DocNest/Features/Documents/DocumentListView.swift:278-290`
   - **Issue:** The primary action says “Import PDFs”, while the native file importer accepts PDFs, ZIP archives, and folders, and the app also supports drop-based folder imports.
   - **Recommendation:** Rename the visible action to “Import…” or “Import Files…” and keep the explanatory help text. This makes the supported workflow discoverable without adding UI.

6. **Low — The File menu omits familiar default shortcuts after replacing the standard group.**
   - **Location:** `DocNest/App/DocNestApp.swift:318-339`
   - **Issue:** “Open Library” and “Create Library” replace the standard new-item group but do not declare the conventional shortcuts users expect, especially Command-O for opening.
   - **Recommendation:** Restore suitable standard shortcuts after confirming they do not conflict with document-level operations (at minimum Command-O for Open Library); expose unavailable commands as disabled instead of silently removing familiar affordances where practical.

#### Recommended order

1. Stop removing standard macOS menus and restore native command groups that have no product-specific replacement.
2. Correct the destructive label-assignment role and clarify the import action label.
3. Convert the quick-label overlay to an anchored popover.
4. Prototype native `List`/`Table` adoption behind the existing sidebar/list behavior and verify keyboard navigation, multi-selection, drag/drop, labels, smart folders, and VoiceOver before replacing the custom views.

Residual verification: conduct a short moderated usability pass with both a first-time user and an experienced macOS user, then perform VoiceOver and keyboard-only checks for the sidebar, document selection, Quick Label, import, and destructive actions. Static source inspection cannot validate visual density, focus behavior, or accessibility-tree quality at runtime.

---

## Complete Post-Implementation App Review

- **Date:** 2026-07-21
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Implement the plan. Redo the complete app review at the very end"

### Result

Reviewed the complete final implementation and affected app workflows: library opening and locking, managed filesystem paths, document import/export, ZIP and URL handling, OCR, updater verification, watch-folder integration, SwiftData persistence, and main-actor UI work.

No further actionable findings were identified in the final implementation diff.

Verified remediation includes package-root confinement for persisted paths, native `fcntl` locking, bounded source/expanded archive/PDF OCR resource use, updater fail-closed signing verification, serialized import task ownership, off-main-actor derived filtering, OCR cancellation and save-failure handling, and private logging for sensitive paths/tool output.

Residual risks:

- The shipped updater intentionally remains unavailable until a production `DocNestUpdateTeamIdentifier` is configured; this is the chosen fail-closed behavior for the current ad-hoc signing setup.
- Runtime stress testing with real adversarial PDFs, archives, and external OCRmyPDF installations remains advisable despite the static checks and unit suite.

Verification: `make test` passed with 201 tests executed, 1 skipped, and 0 failures.

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
