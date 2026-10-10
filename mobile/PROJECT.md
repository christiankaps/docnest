# Mobile App Concept

**Workflow:** ESTABLISHED
**Maturity:** MVP

## Confirmed scope

- DocNest Mobile is an independent mobile app project.
- This folder must be self-contained, with no dependencies on or file references to its containing folder.
- Existing resources such as the DocNest app icon may be reused by copying them into this project.
- The initial concept is established; implementation starts with a Hello World app and proceeds through PLAN.md milestones.

## Purpose and audience

- Problem and intended outcome: Easily retrieve a needed document on a phone and store received PDFs for later retrieval.
- Target users: Individuals organizing personal paperwork. The initial version focuses on personal document management.
- Primary use cases:
  - Open the app and quickly find a stored document.
  - Send a PDF received by email (for example, an invoice) directly to the app for storage.
  - Scan paper documents with the iPhone camera and import them into the document library. Camera import is an important feature for the initial version.
- Capacity target: Comfortably handle hundreds of documents. Focus on private personal paperwork rather than large business archives.

## Platform and delivery

- Language: Implement the initial app in English only. Prepare interface strings and the label starter set for future localization; keep starter-label identities independent of their translated display names.
- Product relationship: A companion app for DocNest on macOS is not currently planned.
- Mobile platforms: iPhone only for the initial version.
- Minimum OS: iOS 27, the current major release as of 2026-10-10. Earlier iOS versions are outside the initial support scope.
- Pricing: The first version is free.

## Capture and inbox

- Camera scanning: Support multiple pages saved as one PDF, automatic edge detection, and crop adjustment before saving. Scans use the same OCR, inbox, and label-suggestion workflow as imported PDFs.
- Label assignment is part of the import-review workflow.
- Import behavior: Run OCR on import and provide smart label suggestions that are easy to accept. Suggestions use document text and the user's previous labeling choices to improve relevance over time. Users assign labels manually or accept suggestions; suggestions do not apply labels automatically. All suggestion processing runs on the iPhone; the technical mechanism is TBD.
- Processing and privacy: OCR and smart label suggestions run entirely on the iPhone. Do not send document content to external processing or AI services. The optional iCloud storage mode remains supported.
- Import review: Save imported PDFs to an inbox for later review and label assignment; labeling is not required during capture.
- Duplicate imports: Detect an identical PDF on import and offer to open the existing document instead of creating a duplicate, preserving its labels. Detection of visually similar scans is not yet specified.
- Inbox lifecycle: Show documents awaiting review. A Done action marks a document reviewed and removes it from the inbox while retaining it in the library. Reviewed documents may have no labels.

## Organization and retrieval

- Retrieval priority: Labels are the primary way to browse and find documents. Full-text search is also supported as a secondary retrieval method.
- Search and filters: Full-text search respects the currently selected labels. Results must match the search text and every selected label.
- Home screen: Make labels the main view, with a clearly visible Inbox count and quick actions for camera scanning and PDF import.
- Document lists: Show the document title, labels, and document date without thumbnails. Sort by document date, newest first, by default.
- Virtual year labels: Automatically derive and assign a virtual year label from the document date's year. Show them in a separate Years section. Year and ordinary label filters combine using AND; for example, 2026 + Invoices shows invoices dated in 2026.
- Labels: Provide an editable starter set: Invoices, Banking, Insurance, Taxes, Health, Home, Work, Vehicles, Contracts, and Receipts. Users can rename, remove, or add labels.
- Organization: Multiple labels per document are a core requirement. Labels organize document views rather than imposing a folder hierarchy. Label filters use AND: a document must have every selected label to appear in results.

## Dates and filenames

- Import date: Store it and show it in document details. It has no role in sorting or filtering. It may supply the suggested document date when OCR finds no reliable date.
- Document naming: Preserve the original filename for imported PDFs. Camera scan names start with the document date in YYYY-MM-DD format followed by an underscore and a descriptive name, for example `2026-10-10_Invoice`. Use the extracted document date, falling back to the suggested import date when no reliable date is found. Suggest the description from OCR, use `Scan` as the fallback, and allow editing during inbox review. Users can rename documents.
- Filename stability: After initial naming, changing the document date does not rename the file. Preserve its existing filename unless the user explicitly renames it.
- Document date: Each document has a document date distinct from file creation and import dates. Extract it from PDF content using OCR where possible. Prefer the document's issue date (for example, invoice date) over a payment due date; flag uncertain choices for review. If OCR finds no reliable date, suggest the import date and flag it for review. Allow users to edit the date during inbox review; changing it automatically updates the virtual year label.

## Document actions and recovery

- Initial document actions: Rename documents, share/export the original PDF, and delete documents.
- Library export: Support exporting the entire library, including PDFs and labels, for backup and moving data. Export format is TBD.
- Library restore: Restore library exports, preserving document names and labels, including on a new iPhone using local-only storage. Merge into an existing library, skip identical PDFs, and retain existing documents. For duplicate PDFs, combine existing and backed-up labels while keeping the current document name.
- Deletion: Keep deleted documents in Recently Deleted for 30 days before permanent removal, with recovery available during that period.

## Storage and app access

- App access: Offer an optional Face ID lock with the iPhone passcode as fallback.
- Storage options: Support local-only storage and an iCloud option. Local-only mode keeps the library on that device. iCloud mode automatically syncs documents across the user's iPhones and restores access on a new iPhone. Downloaded documents remain available offline.
- Storage setup: Ask users to choose Local only or iCloud at first launch, with a short explanation of each option.
- Storage switching: Allow changing mode later in Settings. Copy the library to the selected mode and verify the transfer before completing the switch. Download all documents before switching from iCloud to local-only. Retain the existing iCloud copy until the user explicitly chooses to delete it.

## First-version scope and acceptance

All confirmed capabilities above belong to the first-version concept. Acceptance must cover PDF and camera capture, inbox review, on-device processing, multi-label and year retrieval, document-date handling, local and iCloud storage, recovery, and backup/restore for a library of hundreds of documents. Measurable performance targets remain TBD.

Outside the initial scope: iPad and Android, earlier iOS versions, additional interface languages, a desktop companion role, and external document-processing services.

## Open technical decisions

- On-device suggestion and date-extraction mechanisms.
- Persistence, iCloud synchronization, and conflict handling.
- Backup format and metadata coverage.
- Handling visually similar scans beyond identical-PDF detection.
- Project-local build, tests, integration conventions, and measurable performance checks.

## Working conventions

Current implementation: iPhone-only SwiftUI Hello World app, local app icon, and English string catalog. Product features remain planned; see [PLAN.md](PLAN.md).

Build with Xcode 27 or later. `project.yml` is authoritative for Xcode project generation using XcodeGen; the generated project is included. Use `make help` and `make verify` from this folder. The current gate builds for the iOS Simulator; add behavior tests as implementation grows. See [README.md](README.md) for running and signing.

Keep accepted product decisions in this file. Use Git for coherent verified changes, preserve unrelated work, and integrate directly on main without feature branches or pull requests. Do not publish without explicit authorization.
