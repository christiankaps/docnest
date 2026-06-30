# Agent Instructions

These instructions apply to every AI agent working in this repository.

## Scope

Follow this workflow for every code change, including refactors, regressions, bug fixes, and new features.

Documentation-only edits may use a lighter workflow, but code changes must follow the full process below.
Documentation-only edits do not require AI review or full tests unless they change executable examples, scripts, release behavior, or documented app behavior.
For investigation, review, planning, or suggestions without code edits, do not run the full change workflow. Inspect the relevant files and provide findings or recommendations. Record the result in `ANALYSIS.md` only when the user requested a review, investigation, audit, or other standalone analysis task, as described in [Analysis Documentation](#analysis-documentation).

## Analysis Documentation

Only standalone analysis tasks must be recorded in `ANALYSIS.md` at the repository root. This includes user-requested investigations, reviews, audits, or other read-only assessment tasks that produce findings or recommendations.

Delta review findings from the required change workflow do not need to be recorded in `ANALYSIS.md`. A normal review of a completed implementation diff is part of the code-change gate, not a standalone review task.

- Append a new entry to `ANALYSIS.md` for each standalone analysis task. Never overwrite or delete previous entries; the file is an append-only log with the newest entry on top.
- Each entry must include:
  - the date the analysis was performed (`YYYY-MM-DD`),
  - the AI model that performed it (name and exact model ID),
  - the exact analysis prompt that was requested, quoted verbatim,
  - the analysis result (findings and recommendations).
- Commit `ANALYSIS.md` immediately after the analysis result is written. Use a clear commit message such as `docs(analysis): record <topic> analysis`. Recording an analysis is a documentation-only change, so the full code-change workflow does not apply.

## Branching Policy

- Work directly on the repository's default branch (`main` or `master`, whichever the repository uses).
- Do not create feature branches, topic branches, or working branches for changes.
- Do not open pull requests. Commit and push completed changes straight to the default branch.
- Determine the default branch from git remote metadata rather than assuming `main` or `master`.

## Required Change Workflow

1. Understand the affected code before editing.
2. Before implementing a new feature or fixing a bug, plan the change thoroughly.
3. In the plan, identify likely corner cases, regression risks, affected workflows, data-loss risks, concurrency risks, and test coverage needed before editing.
4. Implement the change.
5. Add or update tests for every new feature or bug fix as part of the same change.
6. Run a normal review of the completed diff.
7. If the review finds issues, fix them and rerun the review until the reviewer reports no further findings.
8. If findings remain after two fix-and-rereview cycles, stop making local patches, perform a deeper analysis of the problem, and rethink the implementation before continuing.
9. Run the full test suite only after the review is clean.
10. Create a commit only after the review is clean and the full test run passes.

Before editing, check the worktree. Do not revert or overwrite unrelated user changes. If unrelated changes exist, leave them alone. If they affect the task, work with them or ask before proceeding.

## Review Expectations

- A normal review is required after implementation. It does not need to be performed by a subagent; the main agent may perform it in a dedicated review pass.
- The review pass is read-only. The reviewer must never edit files, compile, build, run the app, run tests, package artifacts, or execute verification commands.
- Review findings should prioritize correctness, regressions, missing tests, concurrency risks, data loss risks, and UI behavior mismatches.
- When there are no actionable findings, say that explicitly and mention any residual risks or tests the implementer should still run.

### Normal Reviewer Instructions

Keep the review focused, practical, and biased toward catching concrete mistakes before tests and commit.

- Review the diff, changed tests, and nearby affected code paths.
- Prioritize concrete defects: build breaks, incorrect API usage, missing migrations, unsafe file operations, data loss risks, privacy leaks, missing tests for changed behavior, and clear UI regressions.
- Check that the implementation matches the requested scope and does not include unrelated refactors or accidental behavior changes.
- Prefer high-signal findings over broad commentary. Each finding should include the affected file or behavior, why it matters, and the smallest practical fix.
- Do not approve by default. If something is unclear enough to hide a bug, ask for clarification or identify the risk.
- When there are no actionable findings, say that explicitly and mention any residual risks or tests the implementer should still run.

## Testing Expectations

- For new features and bug fixes, write tests unless the project truly has no practical way to cover the behavior.
- Tests should verify documented behavior and public contracts rather than implementation details, private structure, incidental ordering, or current helper internals.
- Prefer tests that could still pass after a valid refactor. Only test implementation details when they are themselves the documented contract or the only practical way to protect against data loss, migration failure, or another high-risk regression.
- Prefer focused tests during implementation, but the final gate after clean reviews is the full test suite.
- Build, build-for-testing, test, static-analysis, archive, release-build, and DMG packaging commands must treat compile warnings as errors. Do not remove or bypass that policy unless the user explicitly asks for a temporary diagnostic run.
- Use the repository testing guide in [docs/testing.md](docs/testing.md) for the canonical commands.

## Documentation Expectations

- If a new feature is implemented, update the requirements documentation in the same change.
- If app behavior changes, update the requirements documentation in the same change.
- Keep high-level documentation aligned with shipped behavior before considering the change complete.
- Document APIs and behavior precisely enough that a useful test can be written from the documentation alone.
- Do not expose unnecessary implementation details in public-facing documentation. Describe observable behavior, inputs, outputs, invariants, errors, persistence guarantees, and compatibility expectations instead of private algorithms or helper structure.

## Private Data and Secrets

- Never commit private data, secrets, credentials, or user-identifying local environment details.
- Treat email addresses, passwords, API keys, access tokens, signing keys, private certificates, and local paths containing usernames as private unless the repository already intentionally uses a public placeholder.
- Before staging or committing, inspect new and modified files for accidental private data. Replace private values with placeholders such as `<email>`, `<password>`, `<api-key>`, or `<local-path>`.
- Do not include private data in tests, fixtures, documentation, comments, release notes, screenshots, generated artifacts, or command transcripts.
- If private data is already present in the worktree, stop and ask before preserving, moving, or deleting it. If private data may already have been committed, stop and report the risk instead of creating more commits.

## Release Instructions

- Before creating a release, check GitHub for the latest published release and derive the next version from that release rather than from local assumptions.
- Use the release version schema `YYYY.MAJOR.MINOR`.
- By default, create a new minor release by incrementing the `MINOR` component of the latest published release.
- Only create a new `MAJOR` component when the release plan explicitly requires it.
- When the release year changes, start a new release line for that calendar year and reset the version to `YYYY.1.0` unless an explicit release plan says otherwise.
- Do not maintain older major lines or older year lines separately. Releases always continue from the latest published version.
- The release branch is `master` or `main`, whichever is the repository's default branch.
- When preparing a release, use the repository's default branch as the source branch unless an explicit repository instruction overrides it.
- Use GitHub or git remote metadata to determine the repository default branch. Do not assume `main` or `master`.
- Agents are allowed and expected to use `gh` and network access for release work.
- After creating a GitHub release, do not wait for or watch the GitHub Actions release workflow until the DMG is uploaded unless the user explicitly asks for that verification. Create the release and report the release URL.

Before creating a release:

- ensure the working tree is clean
- ensure the default branch is checked out
- fetch and fast-forward the default branch when possible
- confirm the local default branch matches origin
- check the latest published GitHub release
- create the next release from the default branch
- verify the new release is marked latest

## GitHub Actions

- When editing GitHub Actions workflows, prefer explicit supported runner and Xcode versions over floating assumptions.
- Verify runner and toolchain availability from GitHub-hosted runner documentation or recent workflow logs before pinning versions.

## UI Changes

- For SwiftUI/AppKit UI changes, preserve macOS-native behavior and existing app workflows unless the user explicitly asks for a behavior change.
- Perform visual verification where practical and note the key windows or states checked.
- Add automated tests for behavior that can be tested reliably.

## Platform-Native Preference

- For every new implementation, first check whether the Swift SDK, Apple frameworks, or standard platform behavior provide a native solution covering the requested functionality or similar functionality.
- Prefer platform-native solutions over custom implementations when they exist.
- If the requested feature is close to functionality provided by the SDK or platform, stop and ask the user whether the native solution should be used before proceeding with a custom implementation.
- If a native solution exists but does not fit the requested design 100%, stop and ask the user whether to use the native solution before proceeding with a custom implementation.

## Swift Code Style

- Keep Swift code clear, small, and easy to follow.
- Prefer native Apple frameworks and existing project patterns over adding abstractions or helper layers without strong need.
- Keep dependencies minimal. Do not add new package or library dependencies unless they are clearly justified and the change cannot reasonably be implemented with the standard library, Apple frameworks, or existing project code.
- Place business logic in the existing domain and infrastructure layers instead of duplicating behavior in views or coordinators.
- Write code comments and documentation for non-obvious types, methods, properties, invariants, concurrency assumptions, filesystem assumptions, and workflow rules.
- Use `///` documentation comments for important APIs and use inline comments sparingly for tricky logic.
- Do not add comments that merely restate obvious code.

## Commit Gate

A code change is ready to commit only when all of the following are true:

- the implementation is complete
- tests were added or updated when required
- requirements documentation was updated when features or behavior changed
- code documentation was added or updated where needed
- the normal review reported no further issues
- the full test run passed

If any gate fails, do not commit yet.
After all commit gates pass, create a commit automatically unless the user explicitly asked not to commit.
