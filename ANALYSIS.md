# Analysis Log

Newest-first record of user-requested read-only project assessments.

---

## Complete Technical Review

- **Date:** 2026-10-03
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "Do a complete technical review"

### Findings

1. **High — Permanent deletion can report success while retaining the original PDF.**
   - **Affected code:** `DocNest/Domain/UseCases/DeleteDocumentsUseCase.swift:37-50`; `DocNest/Infrastructure/Library/DocumentStorageService.swift:126-128`.
   - **Issue:** The use case saves the deletion of the metadata record and then calls a non-throwing, error-suppressing file deletion helper. Any filesystem failure leaves the sensitive original in `Originals/`, without metadata or integrity reporting to locate it.
   - **Impact:** A user-selected permanent deletion can silently fail, retaining content and creating an unmanaged orphan.
   - **Recommendation:** Use a recoverable, library-owned staging/quarantine move before metadata deletion, make every filesystem failure explicit, and preserve recoverable metadata or an actionable cleanup record until final removal succeeds.
   - **Tests:** Inject delete/move failures and assert both document recoverability and accurate user feedback; detect and repair orphaned originals.

2. **High — Closing or switching a library can release its lock before library-scoped work has quiesced.**
   - **Affected code:** `DocNest/App/DocNestApp.swift:582-595,656-669`; `DocNest/App/RootView.swift:614-618`; `DocNest/App/LibraryCoordinator.swift:915-923,1255-1290,1318-1347`; `DocNest/Infrastructure/Library/DocumentLibraryService.swift:419-443`; `DocNest/Domain/UseCases/ExtractDocumentTextUseCase.swift:46-52`.
   - **Issue:** Session close releases the advisory lock and security-scoped access before SwiftUI's later disappearance teardown merely requests cancellation. Import, OCR, and integrity tasks rely on unstructured detached work; cancellation is not awaited and the integrity task opens a separate model container.
   - **Impact:** Work may continue reading or writing a closed library after another process has acquired its exclusive lock, breaking the core ownership guarantee and risking races/corruption. Cancellation UI can also falsely look complete while an OCR subprocess or detached task remains active.
   - **Recommendation:** Let the library session own every library-scoped task; cancel and await them before releasing the lock, model container, or security scope. Avoid independent repair containers while the live library is active.
   - **Tests:** Hold import, OCR, and integrity work at deterministic barriers; close/switch libraries; assert no post-release access and no second-process lock acquisition until all work stops.

3. **High — URL and ZIP imports do not fully bound hostile-input resource use.**
   - **Affected code:** `DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift:361-379,705-729,799-866`.
   - **Issue:** `URLSession.download` receives the entire response before the 512 MB check. ZIP extraction uses `ditto` and repeated full-directory scans, but has no archive-entry-count, path-depth, per-entry, wall-clock, inode, or total temporary-space control; folder expansion also materializes every candidate URL.
   - **Impact:** A remote URL or crafted archive can consume substantial temporary disk, CPU, memory, and inodes despite documented size limits, causing a practical local denial of service.
   - **Recommendation:** Stream downloads with early byte-limit cancellation; preflight archives and enforce entry/path/per-entry/aggregate/time limits; avoid repeated full-tree scans and batch directory candidates.
   - **Tests:** Cover unknown-length and chunked oversized downloads, archive entry storms, deep paths, extraction timeout/overshoot, cleanup, and cancellation.

4. **High — Release artifacts are not distributable through the app's own trust model.**
   - **Affected code:** `project.yml:14-17`; `.github/workflows/release.yml:38-113`; `DocNest/App/AboutWindowController.swift:756-792,992-1027`.
   - **Issue:** The project is configured for ad-hoc signing and the release workflow neither injects a Developer ID identity and trusted updater team nor notarizes/staples the app or DMG. The in-app updater correctly fails closed when no trusted team is configured.
   - **Impact:** Workflow-built artifacts cannot support the advertised automatic update flow and are not suitable as a normally notarized public macOS distribution.
   - **Recommendation:** Configure protected CI credentials for Developer ID signing and notarization, embed the expected team identifier, staple artifacts, and fail releases unless code-signature, team, Gatekeeper, and stapler checks pass.
   - **Tests:** Add an artifact-verification CI step that inspects the generated app and DMG rather than only checking that the archive exists.

5. **Medium — ZIP resolver errors, including the archive safety-limit error, are converted into a misleading empty import.**
   - **Affected code:** `DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift:705-721,818-847`.
   - **Issue:** `extractZipFile` catches its own `archiveExpandsTooLarge` error and returns `nil`; `resolveFileURLsAsync` also catches all non-cancellation resolver errors and returns no candidates. The import result consequently loses the actual validation failure.
   - **Impact:** Users can be told that no PDFs were found instead of that an archive was rejected for safety. This weakens the trust and diagnosability required for an import workflow.
   - **Recommendation:** Preserve typed resolver failures in the import result, show the safe rejection reason, and retain cleanup behavior.
   - **Tests:** Assert that an oversized/archive-limit failure is reported as a failure, not as an empty-folder result.

6. **Medium — Watch-folder status can claim monitoring when no monitor is active or the path later disappears.**
   - **Affected code:** `DocNest/App/LibraryCoordinator.swift:1723-1760`; `DocNest/Infrastructure/Library/FolderMonitorService.swift:94-114`.
   - **Issue:** `recomputeStatuses` returns `.monitoring` for any enabled folder whose path exists, without checking `isMonitoring`. `FSEventStreamCreate`/`FSEventStreamStart` failure therefore appears healthy. The status is only recomputed during a refresh, not when an already monitored folder is removed.
   - **Impact:** The UI can tell users that automatic import is active when it is not, leading to silent missed documents.
   - **Recommendation:** Derive status from the actual monitor registration, surface a monitor-start failure, and revalidate paths from event/error handling or periodic health checks.
   - **Tests:** Simulate stream creation/start failure and path removal after startup; assert non-monitoring status and user-visible recovery guidance.

### Verification and residual risk

- `make test` completed successfully: **200 passed, 1 skipped, 0 failed** (201 total) on macOS 27.0.1, with warnings treated as errors. This verifies the unit/integration target only.
- No UI automation, static analysis, release archive, signed/notarized artifact verification, manual visual check, network release check, or malicious-file stress test was run in this review.
- The repository tree was otherwise clean; the only local item is the pre-existing user-owned untracked `META_AGENTS.md`, which was not read or modified. `INBOX.md`, `LESSONS.md`, and `DECISIONS.md` are empty.

### Overall assessment

The source is well-developed and the existing unit/integration suite is currently green, but the four high-severity items make the current project unsuitable for a public release that promises reliable permanent deletion, single-writer library safety, resilient untrusted imports, and automatic updates. Address findings 1–3 before further feature work; configure and verify the release trust chain before shipping.

## Project State

- **Date:** 2026-10-03
- **AI model:** GPT-5 (`gpt-5`)
- **Prompt:** "State of the project"

### Findings and recommendations

DocNest is an MVP-complete native macOS PDF-library application in a release-hardening phase, not yet ready to be described as public-release-ready. The checked-out commit is `4337183` (`fix: harden verification and import handling`, 2026-09-29) on `main`, and it exactly matches `origin/main` at the time of assessment. The latest local release tag is `2026.14.0`.

- The repository implements the documented local-library workflows: creation/open/restore, PDF import through the shared pipeline, labels/groups/smart folders, search, preview/OCR, watch folders, export/share/Finder integration, migration, and integrity reporting. Its 63 production Swift files have 208 discovered unit/UI test declarations across the test targets.
- The 2026-09-29 hardening commit added warnings-as-errors and static-analysis gates to CI/release workflows; it also rejects unreadable, locked, and zero-page PDFs, preserves nil OCR date fallbacks, and ignores library-package contents in incremental watch-folder events.
- The active `PLAN.md` records unresolved high-risk work: transactional permanent deletion, waiting for library-scoped background work before releasing an exclusive library lock, and bounded download/archive import processing. Current deletion code still saves metadata removal before using a non-throwing stored-file deletion helper; library-close code still releases a lock independently of detached work; download/archive handling still lacks complete streaming and archive-entry limits.
- The public distribution path remains externally blocked: the repository uses ad-hoc signing (`CODE_SIGN_IDENTITY = "-"`) and the release workflow does not provide Developer ID signing, notarization, stapling, or a trusted updater team identity. Resolving this requires protected Apple credentials and team configuration, which must not be invented or committed.
- No current verification was executed for this assessment. The active plan reports that `make test` needs to be rerun on a normal macOS development host because this sandbox cannot run the SwiftUI/Observation/SwiftData macro services. Therefore current build, test, UI-test, analyzer, and release-artifact health remain unconfirmed.
- The working tree contains one untracked, user-owned file, `META_AGENTS.md`. It was not inspected or modified. `INBOX.md`, `LESSONS.md`, and `DECISIONS.md` contain no queued entries.

Recommended next work: finish the three data-integrity/import-containment items in `PLAN.md`, configure signing/notarization outside the repository with protected CI secrets, then run `make test`, `make analyze`, and a signed release-artifact validation on a normal macOS host. Run `make test-ui` for release confidence once the local UI-test runner is available.
