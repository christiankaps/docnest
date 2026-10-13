# PDF Pipe

Workflow: ESTABLISHED
Maturity: MVP

## Product direction

**Main user story:** Quickly rename a PDF from its content while retaining full control. PDF Pipe offers smart suggestions; it never chooses the final name or exports a file without a user action.

PDF Pipe is an iPhone-first, on-device document workbench for iOS 26+. The single automatic OCR flow with user-controlled naming and export is implemented in the current app and share extension. [README.md](README.md) describes how to use it, [ARCHITECTURE.md](ARCHITECTURE.md) records ownership, and [PLAN.md](PLAN.md) tracks final qualification.

## Target journey

1. Open or share one PDF, JPEG, or PNG. PDF Pipe makes a temporary copy and converts an image to PDF when needed. No pipeline picker or separate Run action appears.
2. OCR starts automatically on opening, including when the PDF already has selectable text. Existing embedded text remains intact. For scanned content without text, the app adds an invisible searchable layer. On a mixed page, it adds only missing image text, avoiding duplicates in regions covered by existing text.
3. After OCR and content analysis, the app automatically presents a PDF preview and naming suggestions together. It shows OCR status, document-date candidates, and a weighted word cloud ordered by significance. The highest-ranked date has a distinct appearance and an explicit “Suggested date” label; it is never selected automatically.
4. The user taps date and word chips in any order to build a filename. The live preview shows exactly that order. Selected chips show their order and can be removed. The user may also type a complete filename when suggestions are unsuitable.
5. The user explicitly shares or saves the processed copy. An optional configured folder may be offered as a one-tap destination **after** review. Every import stops for naming; unattended saving and automatic template naming are removed from the target flow.

Automatic OCR is preparation, not an automatic naming or export decision. The user can cancel processing or discard the copy. OCR failure, unsupported OCR modification, or empty analysis must still leave a recoverable preview and manual naming path when the input PDF itself is readable; the app explains that searchable text could not be added.

## Naming rules

- Date suggestions come from document content. Rank labeled document or issue dates above due/service dates, retain plausible alternatives, and expose ambiguity. If none is found, offer a visibly labeled processing-date fallback chip. No date is inserted automatically.
- Word suggestions use deterministic, bounded on-device significance ranking. Early pages carry substantially more weight than later pages. Frequency and available visual prominence also contribute; the frequency and large-text bonuses are capped so repeated body terms cannot overwhelm a prominent single occurrence. Bold/italic count only when PDFKit provides usable traits. Short lines near the beginning get a bounded position bonus. Repeated lines count once rather than disappearing. OCR uses relative line size rather than claimed font styling. The stopword filter removes function words and obvious page/URL fragments, not document topics such as “invoice.” There is no positive keyword list or bonus for particular document terms. Show meaningful weight and stable order; retain a manual word entry for missed terms. Suggestions and recognized text live only for the active session.
- Offer `-` and `_` as separator choices initially; default to `-`. When the user appends a chip after the first, capture the **currently selected** separator before that new part. Changing the separator later affects only future additions. Example: select Date, add Acme with `-`, switch to `_`, add Invoice → `2026-10-05-Acme_Invoice.pdf`.
- Removing a part removes its preceding separator. If the first part is removed, the next part becomes first without a leading separator. Re-adding a removed chip appends it at the end using the then-current separator.
- A direct edit to the complete filename takes precedence over the composed suggestion. To keep chip state honest, direct editing converts the current stem into one custom part and clears chip-selection indicators; Undo restores the immediately preceding composition. Later chip taps append to the custom part using the active separator.
- Add `.pdf` automatically and validate the resulting filename before export. A valid user-confirmed name is required, but no chip selection is mandatory.

## Constraints and safeguards

- Never modify an original, overwrite a destination file, or retain a persistent PDF library. Create only temporary session copies; clean them after export or discard and reclaim abandoned sessions safely. Collisions use a unique name.
- Process on-device without an account or backend. Do not persist document text, word/date candidates, or selection history in settings or logs.
- Preserve existing bounded import/OCR limits until deliberately revised. Encrypted or unreadable input remains rejected. If adding an OCR layer would damage annotations, forms, or signatures, keep the readable copy available for naming/export and explain the OCR limitation.
- Keep light/dark support, the light/dark/tinted icon family, native iPhone controls, accessibility labels and non-color selection indicators. Show processing progress and permit cancellation.
- The new single-flow settings start fresh. Old pipeline definitions and destinations do not need migration or preservation. At cutover, disable legacy unattended execution before removing obsolete settings and code; no old destination is selected automatically.
- Apple Shortcuts integration remains a later milestone. iPad optimization, arbitrary Office/web conversion, cloud processing, document archive, conditional scripting, and automatic routing remain outside this redesign.

## Acceptance

The end-to-end app and share-extension journey is import → automatic OCR → preview with ranked date/word suggestions → user-composed or typed filename → explicit share/save/discard. Searchable original text survives, scanned text becomes searchable when recognition succeeds, and mixed pages gain only missing text. Separator changes affect future joins only. No legacy default can silently save a document. Empty or uncertain suggestions never strand the user. Source preservation, collision handling, cancellation, cleanup, and accurate errors remain regression requirements.

The user chose a short final test suite instead of per-increment tests. Run `make verify` before integrating code. Targeted iPhone verification of the full share, provider, bookmark, and OCR journey remains necessary before claiming device qualification; a signed Release has been installed and launched on an iPhone 14 Pro.
