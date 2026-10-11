# Mobile technical design

This document captures implementation boundaries and platform choices for [PROJECT.md](PROJECT.md). It does not imply that planned components exist. Current code remains the Hello World scaffold.

## Local architecture

Use a small native application with one authoritative metadata model and private original PDFs. Choose the simplest local persistence mechanism during increment 1 and record the concrete schema/layout here before finalizing that increment. No cloud proof, cloud entitlement, account handling, or sync abstraction is required for local delivery.

- Stable document and label IDs are independent of filenames. Content identity supports exact-PDF deduplication; display filename/title carries permanent collision numbering.
- Keep original bytes separate from metadata and derived OCR/search data. User date/label/value changes do not rewrite PDFs.
- Store document dates as calendar dates, so a timezone change cannot change the document's year. Import time is a separate timestamp.
- Model review state and processing state independently. Done is not contingent on OCR completion or labels.
- Version durable metadata. Include optional label units and document-label decimal values when that capability is introduced; avoid speculative future-cloud implementation.
- Stage files and commit metadata recoverably. Interrupted writes must not leave a visible document pointing to missing content or replace the last valid copy.
- Imports, scans, and restores reuse document validation, exact-content duplicate detection, identity, and naming rules. App-private storage allows filenames to remain user-facing metadata while identifiers govern storage.
- Reject encrypted or unreadable PDFs clearly. Reject malformed backups safely. Check available resources and provide useful failure/retry states rather than silently skipping data or partially reporting success.

## Capture and access boundary

A share extension uses App Groups for a durable handoff to the app. Settle the exact main-app/shared-container layout before extension implementation. Capture may write a new payload without reading or exposing protected library content; authentication governs navigation to existing documents.

A locked duplicate capture cannot offer an unauthenticated preview or disclose existing metadata. Use a generic capture result and require authentication to open/review existing content. This follows the accepted library-lock boundary rather than introducing a second privacy mode.

Keep original files protected with suitable native file-protection settings. The app-level Face ID gate does not itself replace filesystem protection. Verify cold launch, app resume, share-sheet/file-picker lifecycle, and app-switcher snapshots without reauthenticating on every transient inactive event.

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
| Local persistence and file layout | 1 | Relaunch, interrupted-write recovery, duplicate/name safety, no Files visibility |
| Resource test corpus and initial timing baseline | 1; refine in 6 and 10 | Hundreds of documents, representative sizes/page counts, bounded work and disk failure |
| Share staging and file protection | 4–5 | Locked capture, process interruption, access boundaries, lifecycle tests |
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
