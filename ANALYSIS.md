# Analysis Log

Newest-first record of user-requested read-only project assessments.

---

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
