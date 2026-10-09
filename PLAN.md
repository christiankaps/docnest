# Remediate Technical Review Findings

## Objective

Resolve every finding from the 2026-10-03 technical review while preserving the local-library format, data ownership, and native macOS workflows. Completion requires a verified, signed release candidate; work that depends on protected Apple credentials is tracked explicitly rather than bypassed.

## Scope and constraints

- Preserve the current `.docnestlibrary` layout. Earlier library compatibility and migrations are explicitly out of scope under the macOS 27 platform policy.
- Treat deletion, library close/switch, imports, and watch folders as high-risk filesystem/concurrency work. Prefer transactional or recoverable state transitions.
- Keep the shared import pipeline authoritative for manual, drag/drop, paste, Services, URL, ZIP, and watch-folder inputs.
- Do not invent, store, or log Developer ID certificates, notarization credentials, team identifiers, or other secrets.
- Complete each milestone with focused regression tests, a read-only diff review, and the documented verification appropriate to its risk.

## Milestones

### 1. Make permanent deletion recoverable and truthful

1. Define a library-owned deletion staging area and a durable cleanup/recovery representation that does not expose user data outside the package.
2. Change stored-file deletion to return failures; stage files before committing metadata removal and restore staged files if the metadata transaction fails.
3. On a final removal failure, keep the document recoverable or record an actionable integrity-cleanup item; never report successful permanent deletion otherwise.
4. Extend integrity scanning/repair to find managed-original orphans and staged leftovers safely.
5. Add tests for move failure, metadata-save failure, final-removal failure, crash-recovery state, and current-format library reopening.

**Exit criteria:** no deletion path can discard the only record of a retained original, and the user receives an accurate outcome.

### 2. Establish library-scoped task ownership before lock release

1. Inventory every task that accesses an open library: import resolution/staging/commit, OCR, integrity repair/reporting, watch-folder scans, previews that write data, and security-scoped access.
2. Introduce session-owned task registration/cancellation and an asynchronous close/switch sequence that cancels and awaits quiescence before releasing the lock, model container, or security scope.
3. Replace or wrap detached library tasks so cancellation propagates and is observed; ensure external OCR processes are terminated and awaited.
4. Route integrity repair through the active session/container or otherwise serialize it under session ownership.
5. Add deterministic barrier tests for close and switch during import, OCR, integrity refresh, and watch-folder work; assert no post-release filesystem/database access and no early competing lock acquisition.

**Exit criteria:** the lock remains held until every library-scoped task is stopped, and cancellation UI/state matches actual task completion.

### 3. Bound and diagnose untrusted import work

1. Replace whole-response URL downloading with a streaming/delegated download that rejects excessive content length early and cancels when received bytes exceed the source limit.
2. Preflight ZIP archives and enforce bounded entry count, path depth, individual-file size, aggregate expansion size, temporary-space/inode use where observable, and wall-clock extraction time.
3. Replace repeated whole-tree archive-size walks and unbounded candidate accumulation with bounded/batched enumeration.
4. Preserve typed resolver and safety-limit errors through `ImportPDFDocumentsResult`; make ZIP/download rejection visible rather than reporting an empty import.
5. Ensure cancellation and every failure path clean up temporary files/directories without suppressing the user-facing error.
6. Add tests for unknown-length and chunked oversized responses, excessive-entry/deep-path/oversized ZIPs, extraction timeout, cancellation, cleanup, and correct summaries.

**Exit criteria:** untrusted URL/archive input cannot exceed documented resource budgets without prompt cancellation, and all rejections are accurately reported.

### 4. Make watch-folder health reflect actual monitoring

1. Derive watch-folder status from both path validity and an active `FSEventStream` registration.
2. Surface stream-create/start failures as a user-visible inactive/error status with retry behavior.
3. Detect a path disappearing after activation and transition status promptly; recover when it returns without duplicating imports.
4. Add tests for failed stream startup, path removal/reappearance, repeated refresh, and status/UI mapping.

**Exit criteria:** the settings UI never labels an inactive or invalid folder as monitoring.

### 5. Produce a trusted public distribution

1. Obtain protected CI configuration from the release owner: Developer ID Application signing identity, team identifier, notarization credentials, and any app-specific authorization required by the chosen notarization mechanism.
2. Update the release workflow to sign the archive with the Developer ID identity, embed the trusted updater team identifier, notarize and staple the app/DMG, and keep ad-hoc signing limited to local development.
3. Add release-artifact verification for `codesign --verify --strict`, expected bundle/team identity, Gatekeeper assessment, stapler validation, and updater configuration consistency.
4. Exercise an update from a prior signed build to a signed candidate and document the operational release prerequisites in the release process documentation without recording secrets.

**Exit criteria:** a CI-produced DMG is Developer-ID signed, notarized, stapled, verifies under Gatekeeper, and passes the app updater's team-identity checks.

### 6. Final integration and release readiness

1. Update the requirements, library-format, import-pipeline, UI-concepts, testing, and release-process documents for any behavior or storage changes.
2. Perform a read-only review of the complete diff, focused tests, and affected workflows; fix actionable findings and re-review.
3. Run `make test`, `make analyze`, and `make test-ui` on a normal macOS host. Run release build/archive and signed-artifact verification after credentials are configured.
4. Validate current-format library opening, permanent deletion recovery, close/switch during work, URL/ZIP import limits, watch-folder recovery, and automatic update installation manually where automation is insufficient.
5. Remove this plan and commit the completed implementation only after all milestones and gates pass.

## Status

In progress (2026-10-03).

- Milestones 1–4 have an initial implementation: library-local deletion staging with integrity reporting; close-time cancellation/awaiting of UI-owned import and OCR work; bounded streamed downloads and ZIP preflight/extraction; and watch-folder status based on active monitoring registration.
- Focused deletion recovery coverage was added. `make test` (202 tests, 1 skipped) and `make analyze` pass. `make test-ui` could not start because macOS LocalAuthentication was already active; no UI test ran.
- Remaining work includes the specified fault-injection and lifecycle regression coverage, manual current-library/workflow validation, final documentation updates, and a release workflow/artifact verification.
- Milestone 5 is blocked pending release-owner-provided protected signing, team, and notarization configuration. No credentials or identifiers will be invented or committed.
