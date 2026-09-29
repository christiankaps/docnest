# DocNest Project

## Identity

DocNest is a native macOS app for creating and using local, PDF-first document libraries. Its deliverable is a Finder-visible `.docnestlibrary` package and a native desktop experience for importing, organizing, retrieving, previewing, exporting, and sharing PDFs.

## Scope and non-goals

In scope: local library lifecycle, PDF ingestion from documented macOS entry points, labels and smart folders, search, previews, watch folders, export/share/Finder access, integrity reporting, and recovery of documented library structures.

Out of scope unless explicitly approved: cloud-first storage, non-PDF document management, rigid user-managed folder hierarchies inside libraries, and non-native replacements for standard macOS interactions.

## Maturity and acceptance

**Maturity:** PRODUCTION.

The app has released versions and must protect existing users, local libraries, documented workflows, and public behavior. A change is accepted when it satisfies applicable requirements, preserves documented compatibility or explicitly records the approved break, has proportionate tests and documentation, passes a clean review, and passes the stable verification gate for code changes.

## Invariants

- User libraries and source PDFs remain local and user-controlled.
- The `.docnestlibrary` package layout, metadata, originals, previews, and diagnostics remain compatible with [docs/library-format.md](docs/library-format.md).
- Every import path uses the documented core pipeline, including duplicate handling and self-import protection.
- Labels and smart folders organize views; they do not impose filesystem folder hierarchies on originals.
- Native macOS interactions and current user workflows are preserved unless a deliberate behavior change is documented.
- No secrets or private user data are committed.

## Engineering and verification policy

Prefer existing project patterns and Apple frameworks. Keep filesystem, migration, deletion, export, import, and watch-folder work conservative and regression-tested. Required stable verification for code changes is `make test`; see [docs/testing.md](docs/testing.md) for focused, optional UI, build, analysis, release, and packaging commands. Build-related commands treat compiler warnings as errors.

## Git policy

Git mode: remote-backed repository (`origin`). Default branch: `main`. Integration strategy: **Direct**—commit verified, coherent changes to `main`; do not create feature branches or pull requests. Determine remote state before releases; GitHub releases define shipped versions.

## Sources of Truth

| Subject | Authoritative source |
| --- | --- |
| Product purpose and navigation | [README.md](README.md), [docs/overview.md](docs/overview.md) |
| Detailed behavior and scope | [docs/requirements.md](docs/requirements.md) |
| Architecture and code ownership | [docs/architecture.md](docs/architecture.md), [docs/project-structure.md](docs/project-structure.md) |
| Library persistence contract | [docs/library-format.md](docs/library-format.md) |
| Import behavior | [docs/import-pipeline.md](docs/import-pipeline.md) |
| Search and organization | [docs/search-and-organization.md](docs/search-and-organization.md) |
| UI principles | [docs/ui-concepts.md](docs/ui-concepts.md) |
| Verification | [docs/testing.md](docs/testing.md) |
| Releases | [docs/release-process.md](docs/release-process.md) |
| Contribution expectations | [docs/contributing.md](docs/contributing.md) |
| Agent operation | [AGENTS.md](AGENTS.md) |

## Operational queues

[INBOX.md](INBOX.md) is user-owned input and may be processed only with user authorization. [DECISIONS.md](DECISIONS.md) and [LESSONS.md](LESSONS.md) are temporary agent queues; consolidate their material contents into the sources above, then remove the entries. Git history is the project record, not these queues.
