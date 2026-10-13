# PDF Pipe architecture

PDF Pipe has one explicit journey: import → automatic OCR and analysis → preview and user-composed filename → user-directed export or discard. The SwiftUI app and share extension embed the same `OneFlowWorkbenchView` and use `OneFlowSessionModel`. There is no pipeline interpreter, template parser, unattended default, or legacy settings reader. The old `pipelines.v1` preference is ignored; old data did not require migration.

## Ownership

- `OneFlowHomeView` handles native Files import, Open In delivery, settings, and the build-date display. `ShareViewController` receives one supported item provider and presents the same workbench.
- `OneFlowSessionModel` owns phase, cancellation, temporary-session lifetime, analysis, filename choices, export copies, and completion. It keeps the working PDF available after an OCR or export failure. App and extension callbacks clean up after successful handoff or discard.
- `DocumentEngine` stages and validates input, converts JPEG/PNG to PDF, and describes the resulting copy. It delegates recognition to `AutomaticOCR` and creates a newly named temporary copy only when the user requests export.
- `AutomaticOCR` renders each page and runs Vision even when embedded text exists. It compares recognized lines with embedded text and PDFKit line bounds, then adds only missing lines as invisible Core Text in a re-emitted PDF. Existing page content is drawn as PDF content, never flattened. When annotations, forms, or signature structures are detected, it retains the original PDF copy and uses the recognized lines only for suggestions. The mixed-page simulator test checks embedded text, selectable OCR text, and source bytes. PDFKit's `page.string` can omit the invisible layer even though its selection API and external PDF text extraction include it.
- `DocumentAnalyzer` ranks dates and words from embedded and newly recognized text. `FilenameComposer` stores ordered parts and the separator captured when each part was appended. Direct editing forms a custom part and supports one-step Undo. `SafeFilename` validates the exact string shown before export.
- `OneFlowSettingsStore` keeps only an optional destination bookmark under `oneFlow.v1` in App Group defaults. Both targets reload it. It never triggers automatic saving. `DestinationWriter` coordinates and atomically publishes explicit folder saves without overwriting an existing file.

## File safety and concurrency

An import is copied into a protected, backup-excluded App Group `Library/Caches/Sessions/<UUID>` directory. App-owned Open In deliveries are moved there before asynchronous work; external originals are opened only for reading. Advisory locks protect active sessions from abandoned-session cleanup by another process. Import and destination writes stream data and check cancellation. The engine is an actor; UI/session state is main-actor owned. Session files are removed after export or discard, and abandoned unlocked sessions are reclaimed on later launch/import. No PDF, recognized text, suggestions, or filename history is persisted by PDF Pipe.

The share extension completes its host request only after an explicit user export and session cleanup; discard cancels the request. Successful handoff does not guarantee that another app or cloud provider permanently retained the file.

## Project and verification

`project.yml` and `make generate` own target membership, plists, entitlements, and signing settings. Both targets support iPhone on iOS 26+. `make verify` runs the short simulator suite, Release static analysis, and an optimized unsigned device build. A signed Release was installed and launched on an iPhone 14 Pro; provider, bookmark, and real-document behavior still needs targeted device qualification. The app build phase stamps a UTC build time into its bundle, displayed locally on Home.
