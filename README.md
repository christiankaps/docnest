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

## Product Principles

- Local first: the library lives on disk, under the user's control.
- PDF first: import, preview, OCR/search extraction, and metadata flow are optimized around PDFs.
- Native macOS feel: keyboard shortcuts, drag and drop, Quick Look style preview behavior, Finder integration, and standard window behavior matter.
- Trustworthy data handling: migration, integrity reporting, duplicate detection, and consistency tooling are part of the product, not afterthoughts.

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

## Library Format

DocNest stores documents in a `.docnestlibrary` package. The package is designed to appear as a single file in Finder while still keeping the data local and inspectable.

Typical contents include:

- `Metadata/` for the local metadata store and manifest
- `Originals/` for imported source PDFs
- `Previews/` for derived preview data
- `Diagnostics/` for integrity reports and related tooling output

This gives the app a strong balance between user ownership and app-managed structure.

## Current Status

The project is already a working native macOS app, not just a scaffold. The repository contains:

- the app implementation in SwiftUI/AppKit
- SwiftData-backed library models and migration support
- import, preview, labeling, watch-folder, and sidebar flows
- tests and product documentation
- GitHub release automation that bakes release versions into the app bundle

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

## Repository Structure

```text
DocNest/
  App/
  Domain/
    Entities/
    UseCases/
  Features/
    Documents/
    Library/
  Infrastructure/
    Library/
    Preview/
  Resources/
  Shared/

DocNestTests/
DocNestUITests/
SampleLibraries/
docs/
scripts/
```

High-level responsibilities:

- `App/`: app lifecycle, scene setup, global coordination
- `Domain/`: entities and use cases
- `Features/`: user-facing UI by product area
- `Infrastructure/`: filesystem, previews, persistence, and library services
- `Shared/`: reusable UI and supporting components

## Documentation

The most useful project documents are:

- [docs/requirements.md](docs/requirements.md) for product goals, scope, and detailed behavior
- [docs/project-structure.md](docs/project-structure.md) for codebase layout and architectural intent

## Why This App Exists

Many document apps are either too simple, too cloud-dependent, or too tied to folder structures that break down over time. DocNest aims to sit in a more durable middle ground:

- local and private
- structured without being rigid
- approachable for personal use
- robust enough for real long-term archives

That combination is the core of the product vision.
