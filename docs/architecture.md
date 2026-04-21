# DocNest Architecture

## Architectural Summary

DocNest is a native macOS SwiftUI application with a pragmatic layered structure:

- `App/` owns process lifecycle, scenes, menu wiring, and top-level coordination
- `Domain/` contains persistent entities and business use cases
- `Features/` contains user-facing views grouped by product area
- `Infrastructure/` contains filesystem, persistence, preview, OCR, and monitoring services
- `Shared/` contains reusable UI elements and small supporting types

The codebase is intentionally not split into many modules. Separation happens by responsibility and runtime role inside one app target.

## Layer Responsibilities

### App

The `App` layer sets up the process, the main window, command menus, focused values, and app-wide integration points such as Services, open URL handling, and library session restoration.

Important files:

- [DocNestApp.swift](/Users/kaps/Projects/docnest/DocNest/App/DocNestApp.swift)
- [RootView.swift](/Users/kaps/Projects/docnest/DocNest/App/RootView.swift)
- [LibraryCoordinator.swift](/Users/kaps/Projects/docnest/DocNest/App/LibraryCoordinator.swift)
- [ServicesProvider.swift](/Users/kaps/Projects/docnest/DocNest/App/ServicesProvider.swift)

### Domain

The `Domain` layer models persisted concepts and reusable business operations. Use cases encapsulate behavior such as importing, exporting, searching, labeling, deletion, and watch-folder management.

Important files:

- [DocumentRecord.swift](/Users/kaps/Projects/docnest/DocNest/Domain/Entities/DocumentRecord.swift)
- [LabelTag.swift](/Users/kaps/Projects/docnest/DocNest/Domain/Entities/LabelTag.swift)
- [ImportPDFDocumentsUseCase.swift](/Users/kaps/Projects/docnest/DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift)
- [SearchDocumentsUseCase.swift](/Users/kaps/Projects/docnest/DocNest/Domain/UseCases/SearchDocumentsUseCase.swift)

### Features

The `Features` layer contains UI organized by product area. `Documents` owns list, thumbnail, inspector, and quick-label interactions. `Library` owns sidebar, label management, smart folders, and watch-folder settings.

### Infrastructure

The `Infrastructure` layer contains concrete services for package access, storage layout, library validation and repair, watch-folder monitoring, OCR extraction, preview support, and schema versioning.

Important files:

- [DocumentLibraryService.swift](/Users/kaps/Projects/docnest/DocNest/Infrastructure/Library/DocumentLibraryService.swift)
- [DocumentStorageService.swift](/Users/kaps/Projects/docnest/DocNest/Infrastructure/Library/DocumentStorageService.swift)
- [FolderMonitorService.swift](/Users/kaps/Projects/docnest/DocNest/Infrastructure/Library/FolderMonitorService.swift)
- [DocNestSchemaVersioning.swift](/Users/kaps/Projects/docnest/DocNest/Infrastructure/Library/DocNestSchemaVersioning.swift)

### Shared

`Shared` contains reusable UI and helper types that are cross-cutting but not business-specific, such as typography, chips, focused commands, and small state helpers.

## Main Runtime Flows

### Library startup

1. `DocNestApp` creates a `LibrarySessionController`.
2. The session attempts to restore the last valid library.
3. If restoration succeeds, `RootView` is shown in open-library mode with a SwiftData model container.
4. If restoration fails or no library is known, the app shows a closed-library state.

### Open-library UI coordination

`RootView` owns the live `LibraryCoordinator`, injects the current `libraryURL` and `ModelContext`, and syncs queried SwiftData entities into the coordinator. The coordinator is the main UI state hub for:

- sidebar selection
- search and label filters
- import/export progress
- selection and inspector state
- watch-folder monitoring setup

### Import flow

All user-facing import entry points funnel into `LibraryCoordinator.importDocuments`, which calls `ImportPDFDocumentsUseCase.execute`.

The use case resolves files, folders, ZIP archives, and downloadable URLs into candidate PDFs, rejects self-import attempts, computes metadata and hashes, copies files into library storage, and inserts SwiftData records.

### Search and organization flow

The coordinator derives filtered document sets and sidebar counts from:

- active and trashed document snapshots
- current sidebar section or smart folder
- label filter state
- text query

Search behavior is delegated to `SearchDocumentsUseCase`, while label and smart-folder management use dedicated domain use cases.

### Watch-folder flow

`LibraryCoordinator` configures a watch-folder controller, which uses `FolderMonitorService` to observe filesystem changes. Detected PDFs are re-routed through the same import use case used by manual imports.

## State Ownership

### SwiftData

SwiftData is the persistent source of truth for documents, labels, smart folders, label groups, and watch folders.

### LibraryCoordinator

`LibraryCoordinator` is the derived and interactive source of truth for view state. It does not replace SwiftData; it translates persisted models into UI-ready state and manages transient workflows.

### Services

Infrastructure services are stateless or narrowly stateful helpers for filesystem and preview/OCR behavior. They do not own UI state.

## Persistence and Filesystem Responsibilities

- `DocumentLibraryService` owns library package creation, validation, repair, persistence of the selected library reference, lock management, and integrity reporting.
- `DocumentStorageService` owns where imported PDFs live inside `Originals/`.
- `ImportPDFDocumentsUseCase` owns import metadata extraction and database record creation.
- `DocNestSchemaVersioning` owns SwiftData schema version history and migration plan.

## Design Principles

- Keep user-visible behavior in features and use cases, not in low-level services.
- Keep filesystem layout decisions inside infrastructure services.
- Keep import behavior consistent across entry points by using one shared import pipeline.
- Keep UI-specific derived state centralized in `LibraryCoordinator` rather than spreading it across many views.
