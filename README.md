# DocNest

DocNest is a native macOS document library for people who want their PDFs to stay local, organized, and easy to retrieve.

The app is built around one core idea: documents should feel as manageable as photos in a photo library, while still remaining accessible in the filesystem. Instead of forcing rigid folder hierarchies, DocNest uses labels, saved filters, fast search, and a dedicated local library package to help users keep invoices, contracts, scans, manuals, receipts, and other PDFs under control.

## What DocNest Is

DocNest is a PDF-first desktop app for:

- creating and opening local document libraries
- importing PDFs from files, folders, drag and drop, paste, services, and watch folders
- organizing documents with labels instead of brittle folder structures
- filtering, searching, previewing, exporting, and sharing documents quickly
- keeping original files stored locally in a user-controlled library package

The product is intentionally macOS-native. It uses native windows, native file dialogs, native drag and drop, native sharing, and a Finder-visible library package instead of a hidden cloud-first storage model.

## Main Features

- Local library creation and reopening
- PDF import from files, folders, URLs, Services, and the Dock
- Recursive folder import
- Hash-based duplicate detection
- Document list and thumbnail modes
- PDF preview and inspector
- Labels with colors and optional emoji icons
- Smart folders based on label combinations
- Label groups for sidebar organization
- Watch folders with automatic import and label assignment
- Search and label-based filtering
- Export, Finder reveal, drag-out, and Share sheet integration
- Library integrity reporting and early self-healing for package structure and metadata backfill
- Self-import protection to prevent recursive imports from the open library package

## Build Requirements

- macOS
- Xcode
- `xcodebuild`

## Build Locally

Build the app:

```sh
xcodebuild -project DocNest.xcodeproj -scheme DocNest -derivedDataPath /tmp/docnest-derived build
```

Run the debug app after a successful build:

```sh
open /tmp/docnest-derived/Build/Products/Debug/DocNest.app
```

## Release Builds

GitHub release builds compile the app from the release tag and bake the version into the bundle at build time.

- release tags use the schema `YYYY.MAJOR.MINOR`
- new releases are cut from `master`
- the next release version should be chosen from the latest published GitHub release
- `MARKETING_VERSION` is derived from the GitHub release tag
- `CURRENT_PROJECT_VERSION` is derived from the workflow run number
- the About window displays both the release version and build number

There is also a local packaging helper:

```sh
scripts/build-dmg.sh
```

Optional local release version injection:

```sh
RELEASE_VERSION=2026.4.1 BUILD_NUMBER=42 scripts/build-dmg.sh
```

## Documentation

Start here:

- [docs/overview.md](docs/overview.md) for product concepts and workflow map
- [docs/architecture.md](docs/architecture.md) for application structure and runtime responsibilities
- [docs/import-pipeline.md](docs/import-pipeline.md) for import behavior across all entry points
- [docs/library-format.md](docs/library-format.md) for the `.docnestlibrary` package layout
- [docs/search-and-organization.md](docs/search-and-organization.md) for labels, smart folders, filtering, and search
- [docs/testing.md](docs/testing.md) for test commands and scope
- [docs/release-process.md](docs/release-process.md) for versioning and GitHub releases
- [docs/contributing.md](docs/contributing.md) for code, test, and documentation expectations
- [AGENTS.md](AGENTS.md) for the required AI agent workflow for code changes

Detailed product behavior remains in [docs/requirements.md](docs/requirements.md), and codebase layout is summarized in [docs/project-structure.md](docs/project-structure.md).
