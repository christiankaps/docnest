# PDF Pipe delivery plan

Status: **functional redesign implemented; final device qualification remains**. [PROJECT.md](PROJECT.md) is the product source of truth. The user chose to delete the old unit suite and replace per-increment testing with a few basic tests in the last increment.

## Completed increments

- [x] **I0 — Cutover:** Record the old simulator baseline (44 unit tests), isolate new settings from `pipelines.v1`, and remove the legacy pipeline UI, configuration reader, template interpreter, unattended execution, and their old tests. Old data was not migrated or retained as a requirement.
- [x] **I1 — Automatic OCR:** Run Vision on every imported page, preserve embedded text, add missing OCR text as an invisible selectable layer, and keep readable PDFs available when modification is unsafe or OCR fails. A focused mixed-page simulator test checks selectable new text and unchanged source bytes.
- [x] **I2 — Naming:** Rank document dates and words, show a processing-date fallback, and compose a name from ordered chips. Each new part captures the active `-` or `_` separator. Manual editing, Undo, validation, and automatic `.pdf` are implemented without rerunning OCR.
- [x] **I3 — One-flow UI:** Replace the pipeline list/Run workflow with direct import, automatic processing, preview, OCR status, date and word chips, and an explicit filename. The app and share extension use the same workbench. A simulator UI smoke test covers import through user naming and discard.
- [x] **I4 — Explicit export and cleanup:** Offer Share, Save to Files, and an optional configured quick-save folder only after a valid user-chosen name. Reuse the protected temporary session and collision-safe writer; remove the old pipeline sources and long UI suite.
- [x] **I5 — Basic tests:** Add two focused unit tests and one short UI smoke test, instead of the previous broad suites. Simulator tests, Release static analysis, and optimized unsigned device build pass. A signed Release was installed and launched on Christians iPhone 14 Pro.

## Remaining qualification

- [ ] Exercise a real scanned PDF, searchable PDF, and mixed PDF on the iPhone, including the share extension, OCR time/memory, selecting words, manual naming, and cancellation.
- [ ] Check Files and third-party folder providers, bookmark reuse/revocation, collisions, and share-sheet cancellation on the iPhone. An install and launch alone do not establish provider behavior.
- [ ] Review light/dark and larger text sizes on the final UI; record any accessibility or layout issue found.

Before integrating further code, run `make verify`. This plan does not authorize App Store distribution or deployment.
