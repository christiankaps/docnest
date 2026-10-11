# DocNest Mobile

Independent iPhone app for personal paperwork. Requires Xcode 27 or later and iOS 27 or later. Current implementation: a private local PDF library with file import, a label-first Library home, multi-label/year filtering, label management, manual date editing, Inbox review, PDF viewing and text search, details, rename, bulk sharing/additive labels, Recently Deleted recovery, native sharing, and PDF export. Scanner, OCR, and backups are planned in later increments.

Open `DocNestMobile.xcodeproj`, choose an iPhone simulator, and run. Physical-device builds require selecting your own development team in Signing & Capabilities.

Run commands from this folder:

```sh
make help
make verify
```

`project.yml` is the configuration source for the Xcode project and app Info.plist. After changing it, run `make generate` with XcodeGen installed. Generated files are included so ordinary builds do not require XcodeGen. Build output and test results stay in `.build/`.

`make verify` builds and runs the unit and UI suites on an iPhone 18 Pro simulator with iOS 27.0. Override the destination when needed, for example `make verify DESTINATION='platform=iOS Simulator,id=SIMULATOR-UUID'`. Use `make test-unit` or `make test-ui` for focused checks (`UI_TESTS=DocNestMobileUITests/LibraryUITests/testName` selects one UI test), and `make build CONFIGURATION=Release` for a Release simulator build. Unit tests use temporary libraries and generate a 300-PDF synthetic corpus; UI tests use isolated app-private test libraries. No personal documents or external fixtures are required. Debug-only test launch routing and fixture generation are excluded from Release builds.

Import with the toolbar button, then browse All Documents, a label, a year, or Inbox. Filter combines every selected label and the chosen year. Manage on the Library home creates, renames, and deletes labels; deleting a label keeps its documents. In a document, Labels assigns multiple labels, Details → Edit Date confirms the document date, and Done completes Inbox review even without labels. Date changes update sorting and the virtual year without changing filenames. Open a document to search, share, or view details. Export PDF is in the viewer's More menu. Identical PDFs offer to open the saved copy; distinct filename collisions receive permanent numbered suffixes. Dates initially use a flagged import-date fallback until manually confirmed; Done alone does not confirm the date. Encrypted PDFs are rejected.

Long-press a document for Share, Rename, Labels, or Delete; swipe for Labels/Delete. Select in a document list shares several original PDFs or adds labels while preserving existing assignments. Selection is limited to that list’s visible documents. Deleted documents leave active lists and can be recovered from Library → Recently Deleted for 30 days. Expired files are cleaned up when the app starts or returns to the foreground. Reimporting an identical retained deleted PDF recovers its existing identity and metadata.

The library is local-only and app-private, absent from Files; imports and exports are independent copies. See [PROJECT.md](PROJECT.md) for accepted product behavior, [ARCHITECTURE.md](ARCHITECTURE.md) for the storage format and technical decisions, and [PLAN.md](PLAN.md) for sequential implementation and verification.

## Icon

`Design/AppIconSource.png` is a copied DocNest master icon. The iOS asset is an opaque PNG conversion of that image. Both files are local; builds require no external project files.
