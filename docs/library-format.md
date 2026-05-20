# DocNest Library Format

## Package Overview

A DocNest library is stored as a macOS package with the extension `.docnestlibrary`. Finder presents it as a single item, but it remains a normal on-disk directory tree internally.

This format is designed to provide:

- local ownership of data
- inspectable structure in emergency or backup scenarios
- a stable place for both user content and app-managed metadata

## Standard Directory Layout

The package contains these required directories:

- `Metadata/`
- `Originals/`
- `Previews/`
- `LocationPhotos/`
- `Diagnostics/`

`DocumentLibraryService` treats these directories as required package structure and can recreate missing ones during repair.

## Metadata

`Metadata/` contains:

- the SwiftData store for the library
- `library.json`, the package manifest
- `.lock`, the cooperative single-instance lock file for an open library

The manifest currently records the library format version and creation date. Format version 2 adds managed physical-location photos.

## Originals

`Originals/` stores imported PDFs copied into the library package.

Storage rules:

- files are grouped by import year and month
- filenames are based on the current document title
- filenames are sanitized for filesystem safety
- collisions append a short content-hash suffix

These rules are implemented in [DocumentStorageService.swift](/Users/kaps/Projects/docnest/DocNest/Infrastructure/Library/DocumentStorageService.swift).

## Previews

`Previews/` is reserved for derived preview data and related caches. The app currently treats it as part of the required package structure even when little or no derived data is present.

## Location Photos

`LocationPhotos/` stores app-managed cover pictures for reusable physical document locations. When a user chooses a location picture, DocNest copies the image into this directory with a filename based on the stable location ID. Removing or replacing the picture removes the old managed copy when possible.

## Diagnostics

`Diagnostics/` is used for integrity and repair-related output, including integrity reports written during validation and repair workflows.

## Versioning

The package format and the SwiftData schema version are related but distinct:

- the manifest contains a package `formatVersion`
- SwiftData persistence uses versioned schemas and a migration plan

`DocumentLibraryService` validates the manifest version and can migrate or repair the package structure as needed. `DocNestSchemaVersioning` handles the database schema side.

The SwiftData schema also stores document-label value rows for labels that define a unit. These rows are supplemental metadata keyed by stable document and label UUIDs. The many-to-many label assignment remains the source of truth for whether a label is assigned; value rows can be pruned when their document or label no longer exists.

The SwiftData schema also stores document availability (`Unknown`, `Digital Only`, or `Physical`), reusable physical locations, and each physical document's optional location UUID. A physical location may reference one managed cover picture in `LocationPhotos/`.

## Validation and Repair

When a library is opened, the app verifies:

- the package exists and is a directory
- all required directories are present
- the manifest can be decoded
- the manifest version is acceptable
- integrity and metadata backfill rules can run when needed

Repair can recreate missing directories and fill in missing metadata for stored documents.

## Invariants

These expectations should remain true:

- imported source PDFs live in `Originals/`
- metadata remains library-local, not global
- a valid library can be opened independently of other libraries
- the package remains understandable from the filesystem alone

Any future change to package layout or manifest structure should update this document and the repair/migration code together.
