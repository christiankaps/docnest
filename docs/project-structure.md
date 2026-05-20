# DocNest Project Structure

## Goal

The project structure separates product behavior, feature UI, and infrastructure concerns without splitting the app into premature modules.

## Directory Layout

```text
DocNest/
  App/
  Domain/
    Entities/
    UseCases/
  Features/
    Library/
    Documents/
  Infrastructure/
    Library/
    Preview/
    OCR/
  Resources/
  Shared/
    Design/

DocNestTests/
DocNestUITests/
SampleLibraries/
docs/
scripts/
```

## Responsibilities

### App

- process entry point
- scene and menu setup
- focused-value command wiring
- library session restoration
- top-level coordination and window state

Representative files:

- [DocNestApp.swift](DocNest/App/DocNestApp.swift)
- [RootView.swift](DocNest/App/RootView.swift)
- [LibraryCoordinator.swift](DocNest/App/LibraryCoordinator.swift)

### Domain

- persistent entities such as documents, labels, watch folders, and smart folders
- business use cases for import, export, search, labeling, deletion, and watch-folder management

### Features

- user-facing views grouped by product area
- document list, thumbnail, inspector, and quick-label flows
- sidebar, label management, smart folders, and watch-folder settings

### Infrastructure

- library package access, validation, repair, and locking
- document storage layout inside the package
- watch-folder monitoring
- preview support and OCR/text extraction
- SwiftData schema versioning and migration

### Shared

- reusable UI building blocks
- command wrappers
- layout helpers
- lightweight state helpers

## Xcode and Project Definition

- The repository contains a versioned project definition in [project.yml](project.yml).
- The generated Xcode project lives at [DocNest.xcodeproj](DocNest.xcodeproj/project.pbxproj).
- The on-disk folder structure maps closely to the Xcode group structure.

## Related Documentation

- [overview.md](docs/overview.md)
- [architecture.md](docs/architecture.md)
- [requirements.md](docs/requirements.md)
