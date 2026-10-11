# PdfPipe architecture

## Targets and shared implementation

- `PdfPipe/`: SwiftUI app, pipeline editor, native Files import, selected v1 icon, and explicit DEBUG-only synthetic UI-test fixture.
- `ShareExtension/`: `ShareViewController` embeds the same SwiftUI workbench. It consumes exactly one supported `NSItemProvider` file, runs the explicit unattended default when configured, and completes the host request after automatic saving and cleanup. It never launches the containing app.
- `Shared/`: compiled into both targets; models, configuration, processing, destination writing, session ownership, and native preview/export adapters.
- `PdfPipeTests/`: source-integrity, OCR text/appearance/rotation, cancellation, import bounds, templates, configuration, export failures/collisions, and cleanup tests.
- `PdfPipeUITests/`: simulator and physical-iPhone app/extension interaction checks.

## Ownership and concurrency

`PipelineStore` and `DocumentSessionModel` run on the main actor. The engine is an actor, so PDF rendering and Vision work happen off the UI actor. Streaming import and destination writes run in worker tasks; cancellation propagates to those workers. Item-provider files are copied synchronously inside their callback before its temporary URL expires.

`DocumentSessionModel` owns the current task, session, and engine. Discard cancels and awaits work before removing files. A failed save retains the active processed result. UIKit export callbacks distinguish cancellation from success; cleanup occurs after the system sheet dismisses. A share completion acknowledges handoff, not permanent recipient storage or cloud sync.

## Persistent configuration

An App Group UserDefaults suite stores one Codable `PipelineConfiguration` snapshot under `pipelines.v1`. Only the app edits configuration; the extension reloads it when invoked. The snapshot holds named ordered steps, template strings, destination bookmarks, unattended flags, and an optional explicit default UUID. Corrupt configuration is reported and is not overwritten.

Folder selection creates a minimal bookmark while security-scoped access is held. Both processes resolve it, balance scoped access, and coordinate writes. Stale/revoked/unavailable access produces an error; it never redirects output. Physical-device proof of cross-process provider access remains required.

## Temporary storage and original preservation

App Group `Library/Caches/Sessions/<UUID>` directories are excluded from backup and protected with complete file protection. A session lifetime lock prevents another app/extension process from cleaning up its active files. A root maintenance lock serializes directory creation and abandoned-session cleanup, including interrupted initialization. Only UUID session directories are managed. Abandoned unlocked sessions are removed on launch/import; metadata is limited to lock files and random identifiers.

Open In deliveries owned by the app are moved immediately from `Documents/Inbox` into a protected session before asynchronous work starts. The app-owned Documents parent is excluded from backup because physical iOS forbids changing the system-managed Inbox directory itself. Rejected deliveries are deleted, and unclaimed leftovers are removed when the app backgrounds. Launch cleanup only sweeps managed sessions: sweeping Inbox during cold launch could delete a delivery whose URL callback is still pending. External originals and symbolic-link targets are never consumed. Unit tests inject an isolated Inbox fixture; real-device checks separately cover the Documents backup flag and actual Inbox delivery.

The engine streams a copy of the source, prepares a separate input PDF, and creates per-run output files. Source names remain available even when unsuitable for export; shared pipeline preflight computes and validates the output filename for both the workbench preview and execution before OCR begins. Source files are opened only for reading. Non-OCR PDF processing preserves PDF bytes. OCR renders each visible crop page into a fresh PDF and adds invisible Core Text glyphs using Vision bounding boxes. Existing text pages skip recognition. Editable annotations/forms are rejected for OCR because re-emission cannot preserve their semantics.

Configured saving uses file coordination, an exclusively created hidden `.pdfpipe-<UUID>.partial` staging file on the destination volume, streamed writes, and `fsync`. Only then does a same-volume `renamex_np(RENAME_EXCL)` publish the final PDF atomically. Name collisions select a new suffix, including collisions appearing during streaming. Providers/filesystems that cannot perform the exclusive rename fail without an unsafe fallback. A failed/canceled write removes staging; if cleanup itself fails, the error identifies the staging filename and asks the user to remove it. Unexpected process termination can leave hidden staging at the user-selected destination, but cannot publish a partially written final PDF. Input is opened before output reservation, preventing a missing input from becoming an empty output. The destination is user-owned permanent output; session files are temporary. No durable jobs or recovery feature is implemented.

A shared privacy manifest is bundled in both targets, declaring App Group preferences and app-container/user-selected file metadata access. No tracking or app data collection is declared. [Apple required-reason API definitions](https://developer.apple.com/documentation/bundleresources/app-privacy-configuration/nsprivacyaccessedapitypes/nsprivacyaccessedapitype) define the reasons.

## Project generation and integration

`project.yml` and `make generate` own target membership, plists, entitlements, and project settings. Both app and extension target iPhone on iOS 26+. Swift 6 compiler warnings are errors. `make verify` regenerates the project, runs all Debug unit/UI tests, then analyzes and builds the unsigned device Release. Release explicitly enables Swift `-O` whole-module optimization, C-family size optimization, and deep Clang analysis during builds/archives. Swift and C-family compiler warnings are errors; Clang analyzer findings are errors via `-analyzer-werror`. Swift 6 strict concurrency/type checks apply to Swift sources; Xcode’s Clang analyzer does not analyze Swift. `make test-release` separately exercises optimized code with testability enabled only for that test invocation. Root direct-to-main Git policy applies; stage only PdfPipe changes and preserve unrelated work. No automatic deployment, publishing, or signing-account configuration is part of development.
