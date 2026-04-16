# DocNest Overview

## Purpose

DocNest is a native macOS document library focused on keeping PDFs local, searchable, and easy to organize without forcing users into brittle folder hierarchies.

The app combines three product ideas:

- one local library package that stores originals, metadata, previews, and diagnostics together
- labels and saved label combinations instead of user-managed storage folders
- strong macOS-native behavior for importing, searching, previewing, exporting, and Finder integration

## Core Concepts

### Library

A `.docnestlibrary` package that contains the local metadata store, original files, derived preview data, and diagnostics.

### Document

An imported PDF with a stable identifier, original filename, stored file path, metadata, OCR/search text, and optional labels.

### Label

A user-defined tag that can be assigned to documents. Labels are the primary organization primitive.

### Smart Folder

A saved combination of labels shown in the sidebar. Smart folders are virtual views, not filesystem folders.

### Label Group

An optional grouping construct for organizing labels in the sidebar. Label groups affect presentation only.

### Watch Folder

A filesystem directory monitored by the app. New PDFs discovered there are imported automatically and can receive predefined labels.

## Main User Workflows

### Library lifecycle

Users create or open a library, and the app restores the last valid library on next launch when possible.

### Import

Users can import from file dialogs, folders, drag and drop, paste, Services, Dock/open URL handling, and watch folders. Import always flows through the same core pipeline.

### Organize

Users assign labels, combine labels into smart folders, group labels in the sidebar, and manage automatic label assignment through watch folders.

### Retrieve

Users browse in list or thumbnail mode, filter by labels, search across metadata and extracted text, and inspect or preview the selected PDF.

### Export and Finder access

Users can open originals, reveal them in Finder, share them, or export them with descriptive filenames.

## Documentation Map

- [README.md](/Users/kaps/Projects/docnest/README.md): entry point for the repository
- [requirements.md](/Users/kaps/Projects/docnest/docs/requirements.md): detailed product behavior and scope
- [architecture.md](/Users/kaps/Projects/docnest/docs/architecture.md): application structure and runtime responsibilities
- [project-structure.md](/Users/kaps/Projects/docnest/docs/project-structure.md): directory layout and code ownership
- [import-pipeline.md](/Users/kaps/Projects/docnest/docs/import-pipeline.md): import behavior across all entry points
- [library-format.md](/Users/kaps/Projects/docnest/docs/library-format.md): `.docnestlibrary` package layout and invariants
- [search-and-organization.md](/Users/kaps/Projects/docnest/docs/search-and-organization.md): labels, smart folders, filtering, and search
- [testing.md](/Users/kaps/Projects/docnest/docs/testing.md): test strategy and commands
- [release-process.md](/Users/kaps/Projects/docnest/docs/release-process.md): versioning and GitHub release flow
- [contributing.md](/Users/kaps/Projects/docnest/docs/contributing.md): code, test, and documentation expectations
