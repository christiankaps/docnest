# PDF Pipe

PDF Pipe helps you rename a PDF from its contents while keeping the final choice yours. Open or share one PDF, JPEG, or PNG on an iPhone running iOS 26 or later. The app makes a temporary copy, runs on-device OCR, then shows the PDF with ranked dates and significant words. It never changes the original or saves a result without a tap.

## Use

1. Tap **Open a document** in the app, or share a file to PDF Pipe. OCR starts immediately, including on PDFs that already contain text. Native PDF text stays in place. On a clear scan with an invisible old OCR layer, Apple OCR replaces that layer in the temporary result; other image text is added as a searchable layer where safe.
2. The document view shows the preview and source-origin label as soon as the temporary copy is ready, with page-based OCR progress and a cancel action inline. When processing finishes, the same view shows OCR status and suggestions from the best available text per page. The origin label says whether the imported document is likely digital, likely scanned, mixed, an image import, or unclear; it describes the source before OCR. Dates are ordered by significance without a recommended marker. When no date is found, a clearly labeled processing-date fallback appears. Suggested words are ordered by significance.
3. Tap date and word chips in any order. The filename updates live and shows selection order; a selected date turns orange. Choose `-` or `_` for the **next** part you append; earlier joins stay as selected. Tap a selected chip to remove it. Add a word manually, or type a complete filename stem and use **Undo manual edit** to restore the prior chip composition. `.pdf` is added automatically.
4. Tap **Share** or **Save to Files**. Every output action is explicit, and a canceled export leaves the working copy available. **Discard** removes it.

The Home screen shows the installed build date and time. An unfinished app document and its draft name reopen after an app restart. OCR runs again to rebuild suggestions; the active temporary copy is removed after export or discard. PDF Pipe keeps no document library.

## Limits

- One file at a time; up to 30 MB and 50 PDF pages. JPEG/PNG inputs may have at most 40 million source pixels and become one-page PDFs. Encrypted or unreadable PDFs are rejected.
- Import copying has a 30-second limit. OCR has a two-minute limit, renders one page at a time at up to 2.5× PDF point resolution and at most four million pixels per page. A synchronous Vision request cannot be stopped mid-call; cancellation is checked between operations.
- OCR attempts every page. It identifies replaceable old OCR conservatively: a page-sized raster image plus exclusively invisible text. Such scan pages are rendered at up to nine million pixels and given a fresh Apple OCR layer in the temporary copy; the original stays untouched. Ambiguous pages retain their embedded text. On mixed pages it adds only missing lines. If the PDF has annotations, forms, or signature structures, PDF Pipe keeps its readable copy and uses the best recognized text for naming suggestions without rewriting the PDF. Other OCR failures also leave a readable copy and manual naming path when import succeeded.
- Date detection covers ISO and common dotted/slashed numeric dates. Context labels determine the date order first; for equal context scores, newer dates come first. Word ranking is bounded and tuned for common English/German documents; suggestions can be wrong or incomplete. The user always chooses the name.

## Build and verification

Xcode 27 and XcodeGen are required. `project.yml` owns the generated Xcode project. From this directory:

```sh
make help
make generate
make build
make test
make verify
make build-release
make flash DEVICE_ID=<paired-iPhone-id>
```

`make test` runs a short unit suite and one simulator UI smoke test. `make verify` regenerates the project, runs that suite, then performs static analysis and an optimized unsigned device Release build. `make flash` performs the same Release analysis with development signing, then installs and launches the app on the specified paired iPhone (`xcrun devicectl list devices` shows its ID). Swift and C-family compiler warnings are errors; Clang analyzer findings are errors. Override `DESTINATION` to use another simulator. `make build-device` checks unsigned device compilation; installing on an iPhone requires Apple development signing for the app, share extension, and App Group.

The simulator suite and Release analysis/build passed on 14 October 2026. This signed Release was installed and launched on an iPhone 14 Pro. Real-file share-extension, Files-provider, and OCR resource checks on the iPhone remain final device qualification; installation and launch alone do not prove those paths.

See [PROJECT.md](PROJECT.md) for product policy, [ARCHITECTURE.md](ARCHITECTURE.md) for implementation ownership, and [PLAN.md](PLAN.md) for the delivery status.
