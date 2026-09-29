# DocNest Agent Guide

## Project at a glance

DocNest is a production macOS application for local, PDF-first document libraries. Preserve its native macOS experience, local-data model, and documented library invariants. Start with [PROJECT.md](PROJECT.md) for project policy and the documentation map.

## Session protocol

At the start of substantial work:

1. Read this file, [PROJECT.md](PROJECT.md), and the Sources of Truth relevant to the task.
2. Inspect [LESSONS.md](LESSONS.md), an active `PLAN.md` when present, and [INBOX.md](INBOX.md).
3. If the inbox has content, tell the user and ask whether they want it processed; it is user-owned and must not be changed without authorization.
4. Check `git status --short` before editing. Preserve unrelated work.

For substantial, risky, cross-cutting, or cross-session work, create or update `PLAN.md` with the objective, key risks, milestones, and verification. Do not create one for small reversible tasks.

At handoff, persist material decisions or recurring lessons in their queues until they are consolidated into an authoritative document. Queues should be empty after successful consolidation; do not leave historical tombstones.

## Change workflow

For every code change:

1. Understand the affected code and applicable requirements before editing. Plan corner cases, regressions, data-loss or concurrency risks, affected workflows, and tests.
2. Prefer Swift and Apple-framework solutions. If a native solution substantially covers a requested custom design but entails a material trade-off, ask the user before choosing the custom route.
3. Make the smallest coherent implementation. Keep domain behavior in `Domain/UseCases`, persistence and filesystem work in `Infrastructure`, and user workflows in `Features` or `App`.
4. Add or update tests for each feature or bug fix. Update requirements and other product documentation for user-visible, storage, import, migration, architecture, or release behavior changes.
5. Perform a read-only normal review of the completed diff, tests, and nearby code. Do not compile, test, or edit during that pass. Fix actionable findings and rereview; after two fix-and-rereview cycles, reassess rather than patching blindly.
6. After the review is clean, run the stable gate in [docs/testing.md](docs/testing.md): `make test`. Run `make test-ui` or `make test-all` when UI wiring is the primary risk or release confidence is needed; UI automation is optional unless explicitly required.
7. Commit only after the required gate passes. Do not claim success without reporting performed verification.

Documentation-only changes use a proportional review and do not require the full code-change gate unless they alter executable examples, scripts, release behavior, or documented app behavior.

## Standalone analysis

For a user-requested investigation, review, audit, or other read-only assessment, append the result to `ANALYSIS.md` before ending the work. Each newest-first entry must include the date, performing model and exact model ID, the user's exact quoted prompt, and findings/recommendations. Commit that documentation-only record immediately using a clear `docs(analysis): ...` message. Do not add routine implementation review findings to `ANALYSIS.md`.

## Review standard

Review for concrete correctness, build/API mistakes, unsafe filesystem behavior, data loss, privacy leaks, concurrency hazards, missing regressions, scope creep, and UI mismatches. When clean, state that there are no actionable findings and identify any residual risk and verification still needed.

## Project constraints

- Never commit secrets, credentials, private certificates, email addresses, user-identifying local paths, or other private data. If existing private data is found, stop and ask before preserving, moving, or deleting it.
- Preserve documented `.docnestlibrary` layout and import invariants. Treat import, validation, migration, deletion, export, and watch-folder changes as high-risk filesystem work.
- Use native macOS interactions and preserve existing workflows unless a behavior change is requested. Visually verify practical SwiftUI/AppKit changes.
- Keep Swift code small, clear, and dependency-light. Use `///` for important non-obvious APIs and comments only for meaningful constraints.
- Prefer existing project tools and targeted checks. Build, test, analysis, archive, release-build, and packaging commands must treat warnings as errors.

## Git and releases

The integration policy is **Direct**: work on default branch `main`; do not create feature branches or pull requests. Make coherent commits and do not mix unrelated user changes.

For a release, follow [docs/release-process.md](docs/release-process.md): verify the default branch and remote state, derive the next `YYYY.MAJOR.MINOR` tag from the latest GitHub release, and create the GitHub release. Do not wait for the release workflow unless the user requests upload verification.

## Sources of Truth

- [PROJECT.md](PROJECT.md): identity, scope, maturity, policies, invariants, acceptance model, and documentation map.
- [docs/requirements.md](docs/requirements.md): product behavior and scope.
- [docs/architecture.md](docs/architecture.md) and [docs/project-structure.md](docs/project-structure.md): architecture and ownership.
- [docs/library-format.md](docs/library-format.md), [docs/import-pipeline.md](docs/import-pipeline.md), and [docs/search-and-organization.md](docs/search-and-organization.md): persistence and core workflows.
- [docs/ui-concepts.md](docs/ui-concepts.md): interaction principles.
- [docs/testing.md](docs/testing.md) and [docs/release-process.md](docs/release-process.md): verification and shipping.
- [INBOX.md](INBOX.md): user-owned asynchronous input; [DECISIONS.md](DECISIONS.md) and [LESSONS.md](LESSONS.md): temporary agent-maintained queues.

When sources conflict, prioritize the current user instruction, then authoritative requirements, specialized/local instructions, established conventions, this guide, and finally inferred defaults. Escalate material contradictions rather than silently resolving them.
