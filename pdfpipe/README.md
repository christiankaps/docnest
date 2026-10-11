# PDF Pipe

An iPhone document workbench: share a PDF or image, process a temporary copy through a saved pipeline, then share or save the result. Originals stay unchanged. There is no document library.

Requires iOS 26 or later. Built with SwiftUI, PDFKit, Vision, Core Graphics, and native system pickers, with no third-party runtime dependencies.

## Use

1. Create a named pipeline in the app. Enable the steps you need with switches: **OCR → Rename → Save to folder**. The order is fixed and each step can run only once in newly saved pipelines.
2. Use `{original}`, `{date}` (local processing date, `yyyy-MM-dd`), and `{text}` in filename templates. Literal text is allowed; `.pdf` is added automatically.
3. Optionally enable **Save to folder** and choose its destination; Save stays last in the pipeline. Turn on **Run unattended** to save without reviewing, and explicitly set **Default for shared files** to run it automatically when sharing to PDF Pipe. Unattended pipelines cannot use `{text}`.
4. Share one PDF/JPEG/PNG from another app to PDF Pipe, or use **Import a document** in the app. In the app, choose a pipeline first, then select the file in Files. The workbench keeps that pipeline selected and starts interactively.
5. Without an unattended default, select a pipeline, review the proposed filename, and run it. Missing text or invalid output names are shown before Run becomes available. Reviewed results allow filename correction, Share, Save to Files, or saving to the configured folder.

Swipe left on a pipeline on the home screen to delete it. Long-press a pipeline to duplicate it or delete it. Disabling the Save step also turns off unattended execution and clears that pipeline as the default.

Saving to a configured folder stages the complete output before publishing its final filename and creates a unique filename on collision; existing files are never overwritten. Removing/deleting the default clears it, so the next shared import shows the chooser. Failed saving leaves the active result available for an alternate export. Canceling the system export picker keeps the copy available. Discard removes the working session.

## MVP limits

- One file, at most 30 MB and 50 PDF pages. Images have at most 40 million source pixels and are downsampled to a maximum 4096-pixel edge for conversion; one image becomes one page at two image pixels per PDF point.
- Imports have a cooperative 30-second streaming-copy limit. OCR has a cooperative two-minute limit and renders one page at a time at up to 4 million pixels. Provider coordination and a synchronous Vision request cannot be forcibly interrupted mid-call.
- OCR detects languages automatically using the installed Vision recognizer. **Skip pages with existing text** is on by default: existing searchable pages are retained and scanned pages still receive OCR. A page containing both text and an unrecognized image is skipped too. Turn the option off to recognize every page; existing text layers are flattened and replaced to avoid duplicate searchable text, which can increase file size.
- OCR preserves visible crop-page appearance but re-emits pages; annotation/form PDFs are rejected for OCR. Use a pipeline without OCR to retain their original PDF bytes. Encrypted/locked PDFs are rejected on import. Signed PDFs are not supported for OCR; the app does not validate signatures.
- Incoming names use the sender's suggested filename, falling back to the provided file URL's basename. If the sender omits the original name, iOS may supply a generic type-based name. PDF Pipe's own share export explicitly includes its output filename.
- No interrupted-session recovery, background retry queue, or guaranteed execution after iOS terminates the share extension. A termination during saving may leave a hidden `.pdfpipe-<UUID>.partial` staging file in the chosen destination; remove that staging file manually. Providers must support atomic exclusive rename; unsupported providers report a save failure and keep the active result available for another export.
- Document-derived fields and Apple Shortcuts integration are later milestones.

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

Verification on 2026-10-11: `make verify` passes on iOS 27.0 (33 unit tests, two UI tests, and unsigned optimized device Release analysis/build). The preceding baseline passed signed installation, 27 unit tests, the app/share-extension UI test, actual Inbox import, and abandoned-session cleanup on an iPhone 14 Pro running iOS 27.0.1. The current signed, optimized Release build (0.1.0, build 1) is installed and launch-checked on that iPhone; the full automated device suite has not been rerun for the new workflow/OCR options. Provider/resource checks remain pending; see PLAN.md for exact coverage.

See [PROJECT.md](PROJECT.md) for product scope and verification status, [ARCHITECTURE.md](ARCHITECTURE.md) for implementation ownership, and [PLAN.md](PLAN.md) for remaining work.
