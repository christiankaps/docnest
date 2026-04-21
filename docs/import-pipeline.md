# DocNest Import Pipeline

## Supported Import Paths

DocNest supports these import entry points:

- file dialog
- drag and drop into the main window
- paste from file URLs or web URLs
- macOS Services
- Dock/open URL handling
- watch folders

All manual entry points route into [ImportPDFDocumentsUseCase.swift](/Users/kaps/Projects/docnest/DocNest/Domain/UseCases/ImportPDFDocumentsUseCase.swift) through [LibraryCoordinator.swift](/Users/kaps/Projects/docnest/DocNest/App/LibraryCoordinator.swift).

Watch folders detect candidate files in [FolderMonitorService.swift](/Users/kaps/Projects/docnest/DocNest/Infrastructure/Library/FolderMonitorService.swift) and then hand the detected URLs back into the same import use case.

## Input Types

The import pipeline accepts:

- direct PDF file URLs
- folder URLs
- ZIP archives
- HTTP/HTTPS URLs that should download to a PDF

Folders and ZIP archives are expanded recursively to PDFs before the actual import loop begins.

## Recursive Folder Import

Folder imports are recursive across:

- file dialog selection
- drag and drop
- paste of folder URLs
- Services
- Dock/open URL handling
- watch folders

The import pipeline enumerates nested subfolders and only keeps PDF files as import candidates.

## Non-PDF Handling

Non-PDF files are ignored during folder and ZIP expansion. If a user selects a folder that contains no PDFs at all, the import result reports that no PDF documents were found to import.

When non-PDF files are passed directly as top-level file URLs, they are counted as unsupported and reflected in the import summary.

## URL Import

When the pipeline receives an HTTP or HTTPS URL, it downloads the file into a temporary location first. The filename is derived from:

1. `Content-Disposition`, if available
2. the last path component of the URL
3. a fallback filename

Downloaded temp files are cleaned up after the import finishes.

## ZIP Import

ZIP files are extracted into temporary directories using the system `ditto` tool. Extracted contents are then scanned recursively for PDFs. Temporary extraction directories are removed after the run.

## Metadata Extraction

For each candidate PDF, the import pipeline computes:

- content hash
- file size
- page count
- extracted text
- best-effort document date
- import timestamp

OCR-aware text extraction is used so both embedded-text PDFs and scanned PDFs can participate in search.

## Duplicate Detection

Duplicates are identified by content hash. The import use case seeds duplicate detection from:

- already persisted documents
- hashes provided by the caller
- pending unsaved document changes in the current model context

This keeps behavior consistent across repeated imports and long-running UI sessions.

## Self-Import Protection

The pipeline explicitly rejects attempts to import:

- the open library package itself
- any folder inside the open library package
- any file resolved from inside the open library package

This protection is applied both to top-level inputs and to files discovered during recursive expansion.

## Progress and User Feedback

The import pipeline resolves all candidate URLs first, then reports progress across the resolved PDF set. Summary feedback includes:

- imported count
- duplicate count
- unsupported count
- download failure count
- general failure count
- no-importable-PDF feedback for empty folder imports

The app intentionally shows count-based summaries rather than per-file detail in toast messages.

## Watch-Folder Behavior

Watch folders are monitored through filesystem events. The monitor performs:

- recursive full scans when needed
- incremental event-based updates for changed files
- recursive detection of PDFs in nested subfolders

Detected files are passed back into the same import pipeline as manual imports, so duplicate handling, self-import protection, storage behavior, and record creation remain consistent.
