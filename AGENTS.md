# Agent Instructions

These instructions apply to every AI agent working in this repository.

## Scope

Follow this workflow for every code change, including refactors, regressions, bug fixes, and new features.

Documentation-only edits may use a lighter workflow, but code changes must follow the full process below.
Documentation-only edits do not require AI review or full tests unless they change executable examples, scripts, release behavior, or documented app behavior.
For investigation, review, planning, or suggestions without code edits, do not run the full change workflow. Inspect the relevant files and provide findings or recommendations.

## Required Change Workflow

1. Understand the affected code before editing.
2. Before implementing a new feature or fixing a bug, plan the change thoroughly.
3. In the plan, identify likely corner cases, regression risks, affected workflows, data-loss risks, concurrency risks, and test coverage needed before editing.
4. Implement the change.
5. Add or update tests for every new feature or bug fix as part of the same change.
6. Run an AI review using a different model than the implementing agent.
7. Start the first review pass with a fast model.
8. Reuse existing review agents when practical instead of spawning new ones for every pass.
9. If the fast review finds issues, fix them and rerun review until that review agent reports no further findings.
10. If the fast review reports no findings, run a second review with a stronger but slower model.
11. Only after all review agents report no further issues, run the full test suite.
12. Create a commit only after the reviews are clean and the full test run passes.

Before editing, check the worktree. Do not revert or overwrite unrelated user changes. If unrelated changes exist, leave them alone. If they affect the task, work with them or ask before proceeding.

## Review Expectations

- The reviewer must be independent from the implementer and must use a different model.
- Review findings should prioritize correctness, regressions, missing tests, concurrency risks, data loss risks, and UI behavior mismatches.
- Do not treat "no findings" from the first fast review as sufficient for code changes. A clean fast review is the gate to the second, stronger review.
- If a later review finds problems, return to implementation, fix the issues, and repeat the review sequence.

## Testing Expectations

- For new features and bug fixes, write tests unless the project truly has no practical way to cover the behavior.
- Prefer focused tests during implementation, but the final gate after clean reviews is the full test suite.
- Use the repository testing guide in [docs/testing.md](/Users/kaps/Projects/docnest/docs/testing.md) for the canonical commands.

## Documentation Expectations

- If a new feature is implemented, update the requirements documentation in the same change.
- If app behavior changes, update the requirements documentation in the same change.
- Keep high-level documentation aligned with shipped behavior before considering the change complete.

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
- the fast review agent reported no further issues
- the stronger review agent reported no further issues
- the full test run passed

If any gate fails, do not commit yet.
After all commit gates pass, create a commit automatically unless the user explicitly asked not to commit.
