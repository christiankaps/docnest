# Implementation plan

Implement one milestone at a time; the full accepted first-version scope is in [PROJECT.md](PROJECT.md). Later milestones remain planned, not implemented.

## 0. Hello World foundation — complete

- Create an independent iPhone-only SwiftUI app targeting iOS 27.
- Copy the master app icon locally and prepare its iOS asset.
- Add an English string catalog and reproducible local build commands.
- Verify a simulator build and launch the Hello World screen.

Verified on 2026-10-10: `make verify` succeeded with Xcode 27; the final app's device family is iPhone only. Installed and launched on the iOS 27 iPhone 18 Pro simulator and visually confirmed the DocNest title and Hello World screen. Physical-device signing is not yet configured. Xcode emitted its standard App Intents metadata-skip warning because this starter app has no App Intents dependency.

## 1. Local library and label-first browsing

- Define document identity, original PDF storage, filename, document date, import date, review state, and labels with stable IDs.
- Establish atomic writes and a persistence schema before accepting real documents.
- Add editable localized starter labels, label-first home, Years, inbox count, and text-only document lists sorted by document date.
- Implement AND filtering and PDF viewing; year labels derive from document dates.
- Verify persistence after relaunch, multi-label filtering, year changes, and filename stability.

## 2. PDF capture and inbox review

- Add PDF file import and a share extension for receiving PDFs from email and other apps.
- Route both entry points through one safe import pipeline; preserve original bytes and filenames and detect identical PDFs.
- Stage share-extension imports safely using a project-local App Group configuration; configure signing identities when needed.
- Add review, manual label assignment, editable dates/titles, and Done without requiring labels.
- Verify duplicate handling, interrupted imports, share handoff, and retained documents after Done.

## 3. Camera scanning

- Add multi-page scanning with edge detection and crop adjustment using platform capabilities.
- Save one PDF through the common import pipeline.
- Generate initial date-first filenames; keep them stable after later date corrections.
- Verify scan cancellation and multi-page import on a physical iPhone.

## 4. On-device processing and search

- Extract existing PDF text and run on-device OCR where needed, with resumable background work.
- Infer issue dates, distinguish due dates, and flag uncertain or fallback dates for review.
- Suggest scan descriptions and labels using document text and previous accepted labeling choices; never apply ordinary labels without acceptance.
- Add full-text search respecting AND label/year filters.
- Evaluate extraction and suggestions on representative synthetic personal paperwork. Test hundreds of documents and define measurable responsiveness targets.

## 5. Document management and local recovery

- Add rename, original-PDF sharing/export, Recently Deleted, restore, and 30-day cleanup.
- Define a versioned backup containing PDFs, labels, document dates, and review metadata.
- Add full-library export and safe restore: merge documents, skip identical PDFs, combine labels, and keep existing names.
- Verify round-trip backups, corrupt backup rejection, duplicate metadata merges, and recovery. Test cleanup with a controllable clock.

## 6. iCloud and storage selection

- Choose the persistence/sync approach and define conflict handling before implementing synchronization.
- Add explicit Local only/iCloud first-launch choice, sync status, and offline downloaded documents.
- Support verified switching in Settings; download everything before switching to local-only and retain cloud copies until explicit deletion.
- Verify with two devices/accounts as appropriate: relaunch, offline edits, conflicts, account availability, interrupted transfers, and restoration on a new device.

## 7. Privacy, accessibility, and release readiness

- Add optional Face ID lock with passcode fallback; define how locked share imports and app-switcher previews behave.
- Check VoiceOver, Dynamic Type, dark appearance, English strings, and localization readiness of starter labels.
- Complete focused automated regression tests and device checks for the full first-version scope.
- Document signing, iCloud/App Group entitlements, backup format, reproducible builds, and release steps locally.
- Verify no external processing, no parent-folder dependencies, and no private data in fixtures. Prepare free distribution; publishing requires explicit authorization.

## Working gate

Current gate: `make verify` (simulator build). Add targeted tests as behavior is implemented and include them in the gate. Do not claim later milestones complete based on a Hello World build.
