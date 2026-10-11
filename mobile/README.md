# DocNest Mobile

Independent iPhone app for personal paperwork. Requires Xcode 27 or later and iOS 27 or later. Current implementation: a private local PDF library with file import, Library/Inbox lists, PDF viewing and text search, details, native sharing, and PDF export. Labels, date editing, review completion, scanner, OCR, and backups are planned in later increments.

Open `DocNestMobile.xcodeproj`, choose an iPhone simulator, and run. Physical-device builds require selecting your own development team in Signing & Capabilities.

Run commands from this folder:

```sh
make help
make verify
```

`project.yml` is the configuration source for the Xcode project and app Info.plist. After changing it, run `make generate` with XcodeGen installed. Generated files are included so ordinary builds do not require XcodeGen. Build output and test results stay in `.build/`.

`make verify` builds and runs the unit and UI suites on an iPhone 18 Pro simulator with iOS 27.0. Override the destination when needed, for example `make verify DESTINATION='platform=iOS Simulator,id=SIMULATOR-UUID'`. Use `make test-unit` or `make test-ui` for focused checks, and `make build CONFIGURATION=Release` for a Release simulator build. Unit tests use temporary libraries and generate a 300-PDF synthetic corpus; UI tests use isolated app-private test libraries. No personal documents or external fixtures are required. Debug-only test launch routing and fixture generation are excluded from Release builds.

Import with the toolbar button, then open a document to search, share, or view details. Export PDF is in the viewer's More menu. Identical PDFs offer to open the saved copy; distinct filename collisions receive permanent numbered suffixes. All dates are initially flagged import-date fallbacks until date review is implemented. Encrypted PDFs are rejected.

The library is local-only and app-private, absent from Files; imports and exports are independent copies. See [PROJECT.md](PROJECT.md) for accepted product behavior, [ARCHITECTURE.md](ARCHITECTURE.md) for the storage format and technical decisions, and [PLAN.md](PLAN.md) for sequential implementation and verification.

## Icon

`Design/AppIconSource.png` is a copied DocNest master icon. The iOS asset is an opaque PNG conversion of that image. Both files are local; builds require no external project files.
