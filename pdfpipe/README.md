# PDF Pipe

An iPhone document workbench: share a PDF or image, process a temporary copy through a saved pipeline, then share or save the result. Originals stay unchanged. There is no document library.

Requires iOS 26 or later. Built with SwiftUI, PDFKit, Vision, Core Graphics, and native system pickers, with no third-party runtime dependencies.

## Use

1. Create a named pipeline. Enable the steps you need: **OCR → Rename → Save to folder**. The order is fixed. OCR skips pages that already contain text by default.
2. For Rename, tap template chips such as **Document date**, **Word 1–3**, `_`, and `-`. Original name, processing date, manual text, and fixed text are also available. The editor shows an example; `.pdf` is added automatically. Tap the remove control on a chip or edit a fixed-text chip. Existing `{original}`, `{date}`, and `{text}` templates remain compatible. `{date}` always means local processing date (`yyyy-MM-dd`); **Document date** uses a date in the PDF and falls back to processing date if none is found.
3. Optionally enable **Save to folder** and choose a destination. To process shared files without review, turn on **Run unattended** and explicitly choose **Default for shared files**. Unattended pipelines cannot require `{text}`. Ranked-word chips resolve automatically if enough words are found.
4. Share one PDF/JPEG/PNG to PDF Pipe, or choose **Import a document** in the app. Direct import asks for the pipeline first, then the file, and starts interactively. Shared import uses the explicit unattended default when one exists.
5. For interactive document-derived naming, run the pipeline, review the detected document date, and choose words from the weighted word cloud. Tapping multiple words puts them after the date in tap order; a manually entered word can correct missing suggestions. Without a selection, the saved template uses its ranked words. Confirm the filename, then share, save to Files, or save to the configured folder. You can still edit the final filename.

Several plausible dates require a choice. If a required word is missing, automatic saving pauses for review and publishes no final PDF. A failed destination save retains the processed copy. Canceling a system export sheet also retains the copy; Discard removes the working session. Swipe left on a pipeline to delete it; long-press to duplicate or delete. Disabling Save also clears unattended/default settings.

Saving to a configured folder stages the complete output before publishing it and creates a unique filename on collision. Existing files and source documents are never overwritten.

## MVP limits

- One file, at most 30 MB and 50 PDF pages. Images have at most 40 million source pixels and are downsampled to a maximum 4096-pixel edge for conversion; one image becomes one page at two image pixels per PDF point.
- Imports have a cooperative 30-second streaming-copy limit. OCR has a cooperative two-minute limit and renders one page at a time at up to 4 million pixels. Provider coordination and a synchronous Vision request cannot be forcibly interrupted mid-call.
- OCR detects languages automatically using the installed Vision recognizer. **Skip pages with existing text** is on by default: existing searchable pages are retained and scanned pages still receive OCR. A page containing both text and an unrecognized image is skipped too. Turn the option off to recognize every page; existing text layers are flattened and replaced to avoid duplicate searchable text, which can increase file size.
- OCR preserves visible crop-page appearance but re-emits pages; annotation/form PDFs are rejected for OCR. Use a pipeline without OCR to retain their original PDF bytes. Encrypted/locked PDFs are rejected on import. Signed PDFs are not supported for OCR; the app does not validate signatures.
- Incoming names use the sender's suggested filename, falling back to the provided file URL's basename. If the sender omits the original name, iOS may supply a generic type-based name. PDF Pipe's own share export explicitly includes its output filename.
- No interrupted-session recovery, background retry queue, or guaranteed execution after iOS terminates the share extension. A termination during saving may leave a hidden `.pdfpipe-<UUID>.partial` staging file in the chosen destination; remove that staging file manually. Providers must support atomic exclusive rename; unsupported providers report a save failure and keep the active result available for another export.
- Document-date detection currently supports ISO and common dotted/slashed numeric dates. Clearly labeled issue dates outrank due dates; ambiguous results need review. The on-device word ranker is deterministic and bounded, with German/English stopwords, heading emphasis, and repeated-line filtering. It can miss meaningful phrases or misrank unusual layouts/languages. Apple Shortcuts integration is a later milestone.

## Build and verification

Prerequisites: Xcode 27 with iOS SDK/simulator support, and XcodeGen installed in the environment (verified with XcodeGen 2.46.0). `project.yml` is the source of the generated Xcode project; change it and regenerate, not the `.pbxproj` directly.

From this folder:

```sh
make help
make generate
make build
make build-device
make build-release
make build-release-simulator
make analyze-release
make test
make test-unit
make test-ui
make test-release
make verify
make clean
```

Override `DESTINATION` for an available simulator, for example:

```sh
make verify DESTINATION='platform=iOS Simulator,name=iPhone 17,OS=26.0'
```

To try the app, open `PdfPipe.xcodeproj` in Xcode, choose the PdfPipe scheme and an iPhone simulator, and press Run. Simulator App Group entitlements use local signing; no physical-device team setup is needed for the simulator.

The integration gate is `make verify`. It regenerates the project, builds/runs all Debug unit and UI tests, then analyzes and builds an optimized unsigned device Release. `make build-release` uses Swift `-O` whole-module optimization, C-family size optimization, and Xcode static analysis. Compiler warnings and Clang analyzer findings fail the build. Clang analysis covers C-family sources; Swift uses Swift 6 compiler/type/concurrency checks, with warnings as errors. `make test-release` runs unit tests with the Release optimizer and testability enabled. `make analyze-release` runs analysis alone; `make clean` removes local build/test artifacts. Generated project files are checked in. Simulator builds use local ad-hoc signing so App Group entitlements are available. `make build-device` checks device-SDK compilation without provisioning; installing on physical devices requires proper Apple signing.

## Device setup and remaining feasibility gate

Both PdfPipe and PdfPipeShare use the user-selected Apple Developer team `QQ2W7FVVXM`, recorded in `project.yml`. Changes to signing settings should be recorded there before regenerating. Verify provisioning for the shared App Group matching `APP_GROUP_IDENTIFIER` (default `group.com.kaps.pdfpipe`). The two targets must share the same group; the app shows a configuration error rather than silently creating isolated settings if group storage is unavailable.

No credentials, signing identities, or invented team identifiers are included. Do not enable automatic account/provisioning changes without the release owner's authorization.

Before distribution, test real-device sharing from Files and other host apps, app-to-extension folder access, iCloud/third-party destinations, revoked permissions, extension memory/termination behavior, cancellation and interrupted-session cleanup. Simulator checks do not establish this physical-device feasibility gate.

Current simulator verification and remaining targeted physical-device checks are recorded in PLAN.md. The prior iPhone baseline covered installation, 27 unit tests, app/share-extension interaction, actual Inbox import, and abandoned-session cleanup on an iPhone 14 Pro running iOS 27.0.1. It predates the document-derived naming implementation. Provider/resource behavior remains to be verified where simulator evidence is insufficient.

See [PROJECT.md](PROJECT.md) for product scope and verification status, [ARCHITECTURE.md](ARCHITECTURE.md) for implementation ownership, and [PLAN.md](PLAN.md) for remaining work.
