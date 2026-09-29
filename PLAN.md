# Remediate Analysis Findings

## Objective

Revalidate the findings recorded in `ANALYSIS.md`, fix every still-relevant issue that can be safely resolved in this repository, verify the results, and remove the obsolete analysis log at completion.

## Constraints and risks

- Preserve existing local-library data, lock ownership, import, and deletion invariants.
- Release signing, notarization, and trusted updater identity require protected Apple credentials and values not present in the repository; do not invent or commit them.
- Do not include the user-owned untracked `META_AGENTS.md` in this work.

## Plan

1. Map each prior finding to current code and recent remediation commits; distinguish resolved, actionable, and credential-dependent items.
2. Fix actionable source, test, documentation, and workflow issues with focused regression coverage.
3. Perform a read-only diff review, then run the required stable test suite and relevant focused checks.
4. Persist any external release prerequisite in the project source of truth, remove `ANALYSIS.md`, and commit/push the coherent change.

## Progress

Completed in the current change:

- CI and release workflows now enforce warnings as errors; both run static analysis.
- Imports reject unreadable, locked, and zero-page PDFs.
- Queued OCR preserves explicit nil fallback dates.
- Incremental watch-folder events ignore `.docnestlibrary` package contents.

Remaining high-risk remediation requiring further implementation: transactional permanent deletion, library-scoped task quiescence before lock release, bounded streaming downloads/archive extraction, and release signing/notarization. The latter requires protected Developer ID and Apple notarization credentials and a trusted team identifier; do not invent them.

Verification is blocked in this sandbox because `swift-plugin-server` cannot run SwiftUI, Observation, and SwiftData macros. Re-run `make test` on a normal macOS development host before commit.
