# Mobile technical design

This document captures implementation boundaries and platform choices for [PROJECT.md](PROJECT.md). The local PDF library, labels, dates, and Inbox review are implemented; later capabilities remain planned as tracked in [PLAN.md](PLAN.md).

## Local architecture

Use a small native application with one authoritative metadata model and private original PDFs. No cloud proof, cloud entitlement, account handling, or sync abstraction is required for local delivery.

- Stable document and label IDs are independent of filenames. Content identity supports exact-PDF deduplication; display filename/title carries permanent collision numbering.
- Keep original bytes separate from metadata and derived OCR/search data. User date/label/value changes do not rewrite PDFs.
- Store document dates as calendar dates, so a timezone change cannot change the document's year. Import time is a separate timestamp.
- Model review state and processing state independently. Done is not contingent on OCR completion or labels.
- Version durable metadata. Include optional label units and document-label decimal values when that capability is introduced; avoid speculative future-cloud implementation.
- Stage files and commit metadata recoverably. Interrupted writes must not leave a visible document pointing to missing content or replace the last valid copy.
- Imports, scans, and restores reuse document validation, exact-content duplicate detection, identity, and naming rules. App-private storage allows filenames to remain user-facing metadata while identifiers govern storage.
- Reject encrypted or unreadable PDFs clearly. Reject malformed backups safely. Check available resources and provide useful failure/retry states rather than silently skipping data or partially reporting success.

### Implemented local format

`LibraryStore` is an actor that serializes imports, reads, exports, and existing-text searches off the UI actor. The authoritative library lives at `Library/Application Support/DocNestLibrary` inside the app sandbox:

```text
DocNestLibrary/
  Documents/<UUID>/original.pdf
  Documents/<UUID>/metadata.json
  Staging/<UUID>/...
  organization.json
```

Each metadata record contains schema version, stable UUID, display filename, SHA-256 content hash, byte/page counts, calendar document date (year/month/day), date provenance, import timestamp, review state, and independent processing state. The immutable schema-1 import record uses `importFallback`, `inbox`/`reviewed`, and `notStarted`. User edits are overlaid from the organization snapshot; processing remains a later increment. JSON timestamps use Foundation Codable's seconds since 2001-01-01 UTC. Calendar dates use the local Gregorian capture date and do not change year when the timezone changes. No separate database or rebuildable catalog is needed for hundreds of records.

Import acquires temporary security-scoped access and coordinates a read of the source. It copies bytes into Staging, requires a regular file (rejecting copied symbolic links), rejects encryption (even an empty-password PDF), verifies readable pages, hashes in 1 MiB chunks, and checks duplicates before resolving names. Case-insensitive, Unicode-normalized filename comparisons avoid ambiguous collisions; control characters/path separators are sanitized. Original spelling is otherwise retained, including extension case. The numbered name is durable metadata and the title omits only the extension.

After writing metadata atomically, a same-volume directory rename publishes the complete document. Startup removes unpublished Staging transactions and loads only complete published records. A published import survives termination before UI acknowledgement; reimport detects the same content. Unexpected/missing/corrupt records fail closed with files preserved and a Retry action; startup never resets a damaged library. Newer schemas are rejected before decoding their fields. File-protection attributes use `completeUntilFirstUserAuthentication`; the later library-lock increment must review the capture/access policy.

The version-2 `organization.json` snapshot (reads version 1 without resetting edits) stores the label catalog and per-document assignments, optional manual calendar date, review state, display filename override, and optional deletion timestamp, keyed by stable document UUID. All organization mutations use one atomic, protected file replacement; in-memory state is updated only after the write succeeds. Label deletion removes its assignments in the same replacement. PDF bytes and import metadata are never rewritten. A terminated write exposes either the previous snapshot or the complete new snapshot; unpublished temporary files are not authoritative. Corrupt snapshots, unknown versions, invalid dates, and dangling assignments fail closed.

Rename changes only the display filename override and uses the same collision allocator as import, reserving names of active and retained deleted records. Filename uniqueness is checked on effective names, not immutable import names. Bulk labeling commits all additive assignments in one snapshot; bulk sharing prepares original-byte copies with the current names and removes already prepared copies if any item fails.

Soft deletion commits a timestamp while retaining the original directory and all metadata. Active reads, previews, search, exports, and edits exclude deleted records. Recently Deleted exposes recovery until 30 elapsed days (30 × 86400 seconds), using an injectable clock for verification. Reimporting identical retained content recovers the existing identity without resetting edits or Done. Names remain reserved during retention, so recovery keeps the filename. At startup and foreground activation, cleanup atomically publishes purged UUID tombstones and removes their organization edits before removing directories. Startup skips tombstoned directories, including partially removed ones, and retries removal. Failures are surfaced; tombstones remain durable for retry and prevent damaged remnants from becoming active documents. No exact-time background execution is promised.

On first opening a library without an organization snapshot (including increment-1 libraries), seed the ten starter labels once. Existing snapshots, including an intentionally empty label catalog, are never reseeded. Starter UUIDs and enum keys are stable; default names come from the English string catalog, and optional user names override localization. Custom labels use random UUIDs. Names are trimmed and must be nonempty, free of control characters, and unique under case-insensitive Unicode-normalized comparison at creation/rename. Translation does not change identity.

Saving a date records `manual` provenance, even if the chosen date equals the fallback. Done changes only review state and never confirms a fallback date. Document dates govern sorting and virtual years; a filter holds multiple ordinary label IDs and at most one year, all combined with AND. Navigation holds document UUIDs and resolves current metadata through the observable model, so edits update the viewer details, lists, filter results, years, and Inbox counts immediately. Deleting an active filter label clears that label from the filter.

Share/export copies are created under an app-private temporary `DocNestExports/<UUID>/<filename>` directory. The system receives these copies, never live-library URLs. Sharing uses a native activity sheet; export uses SwiftUI's file exporter with a file transfer representation and explicit suggested filename. Copies are removed after completion/cancellation or next library load. The app's generated Info.plist explicitly disables file sharing and opening documents in place. Its source is `project.yml`; there is no document-provider extension or cloud entitlement.

The viewer uses PDFKit without saving mutations to originals. Existing-text search runs in the store and returns page indices, match ranges, and snippets; the viewer highlights/navigates to that range. The current UI also provides native list Select mode scoped to visible documents, additive bulk labels, multi-PDF activity sheets, Labels/Delete swipes, Share/Rename/Labels/Delete context menus, and Recently Deleted recovery. Selection is intersected with visible IDs when filters or review state change. Selection hides the tab bar so it cannot overlap the bulk-action toolbar; label sheets use the established label-selection rows outside list edit mode. The current UI supports a label-first Library home, Inbox, label management and assignment, AND/year filtering, date editing, review completion, Settings, PDF details, viewing, import, existing-text search, sharing, and PDF export. OCR and whole-library backups remain later increments.

## Library lock and capture boundary

`LibraryLockController` owns the optional, persisted `libraryLockEnabled` preference and one process-local authenticated session. A fresh process is locked when enabled. Enabling and disabling require successful `LAContext` device-owner authentication; `.deviceOwnerAuthentication` lets iOS offer Face ID and device-passcode fallback. Each attempt uses a fresh context with no grace/reuse interval. Backgrounding invalidates pending authentication and rejects stale success callbacks by generation. Transient inactivity covers content but does not relock or cancel authentication; backgrounding relocks immediately, and foregrounding never authenticates implicitly. The app includes the Face ID usage description generated from `project.yml`.

One synchronized `LibraryAccessPolicy` is injected into the actor and UI. Every live-library read/write entry point checks it before new work; cleanup of already prepared export copies remains allowed. A transaction already authorized before backgrounding can finish, but its completion cannot disclose a duplicate while locked. A default store pointed at the live root also starts locked when the persisted preference is enabled; isolated custom roots remain useful for tests. All app UI uses the app-owned store and controller. This is an app access boundary, not PDF encryption or a replacement for iOS sandbox/Data Protection.

A UIKit `PrivacyShield` is attached to the app window. Scene deactivation synchronously installs an opaque neutral cover before the next SwiftUI render/snapshot; SwiftUI scene-phase observation also maintains lock state. When fully locked, the window's accessibility elements are restricted to the cover, including above presented private sheets. Underlying SwiftUI navigation, details, and edits remain mounted, so backgrounding does not cancel system tasks. A narrowly registered native activity/file-picker/export task may finish using its already authorized independent copy or incoming input. On active return, the cover protects the app underneath that presentation; when the task ends, the full unlock cover returns. Inactive/background snapshots cover the entire window. Native task registration is explicit and balanced at presentation/dismissal; do not grant this exception to arbitrary app-owned sheets.

`CaptureInbox` accepts only new PDF input and returns an opaque receipt UUID, never document identity, metadata, duplicate status, or a library count. It rejects sources inside the configured live library or capture queue, including symlink aliases. It coordinates/security-scopes the external read, validates through the same PDF validator, and publishes a complete protected capture directory by same-volume rename:

```text
Library/Application Support/DocNestCapture/
  Staging/<UUID>/<filename>, capture.json
  Pending/<UUID>/<filename>, capture.json
```

The schema-1 manifest contains capture UUID, safe incoming filename, and capture timestamp. The queue is separate from the live library; it requires no catalog access and does not deduplicate while locked. At unlocked opening, it drains through `LibraryStore.importPDF`, preserving capture date, duplicate metadata, naming, and Inbox rules. Remove a committed queue item only after import commits; termination between those steps becomes an exact-content retry, not a second document. Failed/interrupted imports and corrupt manifests retain pending payloads for retry; partially committed batches refresh visible library state. Relocking stops new imports and leaves the rest queued. Locked success/failure notices contain only incoming-capture information. Corrupt committed captures are never silently discarded.

Live originals, organization snapshots, queue payloads/manifests, and export directories use `completeUntilFirstUserAuthentication`. This supports capture and already authorized system tasks after the device's first unlock without claiming access before first unlock. The Face ID gate does not itself encrypt files; stronger file protection must preserve the accepted capture/task behavior and be separately qualified. The share extension in increment 5 will use a durable App Group handoff into this private queue and must not read the live catalog. App Group identifiers, signing, and scanner entry points are not configured in increment 4.

Simulator tests inject authentication only in Debug with a valid UUID-scoped synthetic test root and an isolated preferences suite. Production/Release never contains this bypass. Tests cover lifecycle, stale callbacks, locked store entry points, presented-sheet accessibility, native task completion, cold launch, capture rejection/duplicates/aliases, and interrupted drains. Actual Face ID/passcode behavior, hardware file protection, and app-switcher snapshot capture require physical-iPhone checks; these remain pending in PLAN.md at the user's request.

## Native capabilities

| Area | Direction |
| --- | --- |
| App shell | SwiftUI NavigationStack, TabView, standard lists/forms, toolbars, menus, and sheets |
| Search and filters | Native search controls; app-owned AND predicate and single-year selection |
| PDF viewing | PDFKit with visible Share/Details; native text search where text exists |
| Sharing | Native activity sheet via ShareLink or UIKit integration if needed for multi-item/lifecycle handling |
| PDF/backup files | System document picker and export APIs; copies only, no external live-library editing |
| Incoming PDFs | Share extension plus durable App Group staging |
| Scanning | VisionKit document camera with multipage/crop review |
| Scanner entry | UIKit Home Screen quick action, handling cold launch and running-app activation |
| OCR | Vision text recognition and existing-PDF text extraction; English and German |
| Dates | Native date entry; local extraction rules and uncertainty/provenance in metadata |
| Authentication | LocalAuthentication with device-owner authentication and passcode fallback |
| Accessibility/localization | Dynamic Type, VoiceOver, SF Symbols, String Catalogs, locale-aware numeric formatting |

Use system appearance and navigation rather than recreating native scanner/share controls. Platform choices guide implementation; validate exact APIs against the installed SDK as each increment is built.

## Processing and search

Maintain a persistent queue with bounded processing, retry state, and work cancellation/invalidation when documents are removed. Prefer existing PDF text before image OCR. Keep original PDFs untouched and store derived results by page.

Apply late results only where compatible with the user's current edits. Treat date candidates and label suggestions separately from accepted user metadata. Preserve Done status. OCR retries must not duplicate documents or erase labels, values, or manual dates.

Library full-text search combines text with selected labels and at most one year. OCR-based in-document search shows snippets and navigates to pages; an external OCR index is not automatically a searchable PDF text layer. Do not add PDF rewriting or precise highlight overlays to the initial scope.

Start with a single text/history-based suggestion pipeline. Evaluate useful suggestions on synthetic English/German paperwork, including recurring issuers. No custom model training or Foundation Models dependency in local delivery.

## Values, recovery, and backup

Use canonical decimal representations rather than binary floating-point for user values and aggregates. Support negative entry explicitly; test local separators, zero/missing, invalid input, six fractional places, and aggregate precision. Apply all product constraints in PROJECT.md.

Soft deletion retains PDF and metadata for recovery. Cleanup is based on elapsed retention and resumes when the app can execute; do not promise that iOS will run a job at an exact deadline.

Define a versioned backup manifest and payload layout in increment 9. Validate payloads and identifiers before mutations, safely resolve filename collisions, and preserve existing documents. Implement the accepted metadata merge/conflict policy without treating restore as future live-sync behavior. A conflict report must remain actionable until resolved or deliberately dismissed.

## Decisions to resolve within their increments

| Decision | When | Required evidence |
| --- | --- | --- |
| Local persistence and file layout | Resolved in 1; see schema above | Relaunch, interrupted-write recovery, duplicate/name safety, no Files visibility |
| Resource test corpus and timing targets | Baseline in 1; refine in 6 and 10 | 300 synthetic PDFs; see PLAN.md for measurements; set device targets as processing is added |
| Share staging and file protection | Private queue and protection chosen in 4; App Group handoff in 5 | Locked capture, process interruption, access boundaries, lifecycle tests |
| Date extraction, multilingual parsing, and search indexing | 6 | English/German fixtures, ambiguous dates, page mapping, user-edit precedence |
| Suggestion matching and history | 7 | Repeatable fixtures, explicit acceptance, no regressions to manual edits |
| Backup encoding, label-ID matching, review/deletion metadata coverage | 9 | Round-trip, corrupt input, duplicate and metadata-conflict tests |

Make reversible engineering choices within the accepted scope. Escalate only a material product conflict or a change to the established privacy/data contract. These decisions do not require speculative cloud infrastructure.

## Later cloud work

After local delivery, evaluate the simplest native private CloudKit-backed approach that can synchronize both metadata and PDFs. A stored path alone does not synchronize a file. Automatic SwiftData/Core Data synchronization is a candidate, not a finalized architecture. Consider CKSyncEngine only if validated requirements justify owning more synchronization logic.

Prove schema, PDF transport, account changes, offline edits, deletion, and conflicts on two devices. Avoid dual iCloud Drive/CloudKit systems. Treat download completeness and storage switching as separately verifiable features; retaining cloud copies creates a merge problem when switching back. Preserve values, dates, labels, and review state. Never use the future restore/sync work to block the initial local implementation.

## Platform references

- [SwiftUI ShareLink](https://developer.apple.com/documentation/swiftui/sharelink)
- [VisionKit document camera](https://developer.apple.com/documentation/visionkit/vndocumentcameraviewcontroller)
- [Home Screen quick actions](https://developer.apple.com/documentation/uikit/add-home-screen-quick-actions)
- [Vision text recognition](https://developer.apple.com/documentation/vision/recognizetextrequest)
- [PDFKit search](https://developer.apple.com/documentation/pdfkit/search-operations)
- [LocalAuthentication policy](https://developer.apple.com/documentation/localauthentication/lapolicy/deviceownerauthentication)
- [Background execution strategies](https://developer.apple.com/documentation/backgroundtasks/choosing-background-strategies-for-your-app)
- [SwiftData cloud synchronization](https://developer.apple.com/documentation/swiftdata/syncing-model-data-across-a-persons-devices)
