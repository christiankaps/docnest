# PDF Pipe

Workflow: ESTABLISHED
Maturity: MVP

## Product direction

**Main user story:** Quickly rename a PDF from its content while retaining full control. PDF Pipe offers smart suggestions; it never chooses the final name or exports a file without a user action.

PDF Pipe is an iPhone-first, on-device document workbench for iOS 26+. The single automatic OCR flow with user-controlled naming and export is implemented in the current app and share extension. [README.md](README.md) describes how to use it, [ARCHITECTURE.md](ARCHITECTURE.md) records ownership, and [PLAN.md](PLAN.md) tracks final qualification.

## Target journey

1. Open or share one PDF, JPEG, or PNG. PDF Pipe makes a temporary copy and converts an image to PDF when needed. No pipeline picker or separate Run action appears.
2. OCR starts automatically on opening, including when the PDF already has selectable text. On clearly scanned pages with a page-sized image and only invisible embedded OCR text, the temporary result replaces that old text layer with Apple OCR. Native or uncertain PDF text stays intact; mixed pages gain only missing image text. Scans without text receive an invisible searchable layer.
3. Once the temporary copy is prepared, the app shows its PDF preview and an inline progress bar while OCR continues. After OCR and content analysis, naming suggestions appear in the same document view. A visible, accessible label describes the imported file as likely digital, likely scanned, mixed, image import, or unclear; it reflects the source before OCR and does not claim certainty where the PDF structure is ambiguous. The screen also shows OCR status, document-date candidates ordered by significance, and a weighted word cloud. No date is highlighted as a suggestion; only a date chosen by the user turns orange. Suggestions use the best available text per page: embedded text for native pages, Apple OCR for clear scans, and embedded plus missing image text for mixed pages.
4. The user taps date and word chips in any order to build a filename. The live preview shows exactly that order. Selected chips show their order and can be removed. The user may also type a complete filename when suggestions are unsuitable.
5. The user explicitly shares the processed copy or saves it through the Files picker. Every import stops for naming; unattended saving and automatic template naming are removed from the target flow.

Automatic OCR is preparation, not an automatic naming or export decision. The user can cancel processing or discard the copy. OCR failure, unsupported OCR modification, or empty analysis must still leave a recoverable preview and manual naming path when the input PDF itself is readable; the app explains that searchable text could not be added.

## Naming rules

- Date candidates come from document content. Rank labeled document or issue dates above due/service dates; within the same contextual rank, put newer dates before older ones. Retain plausible alternatives and expose ambiguity. If none is found, offer a visibly labeled processing-date fallback chip. No date is inserted automatically or marked as recommended; selected dates are orange and retain a non-color order indicator.
- Word suggestions use deterministic, bounded on-device significance ranking. Early pages carry substantially more weight than later pages. Frequency and available visual prominence also contribute; the frequency and large-text bonuses are capped so repeated body terms cannot overwhelm a prominent single occurrence. Longer words receive a small capped bonus. Bold/italic count only when PDFKit provides usable traits. Short lines near the beginning get a bounded position bonus. Repeated lines count once rather than disappearing. OCR uses relative line size rather than claimed font styling. The stopword filter removes function words and obvious page/URL fragments, not document topics such as “invoice.” There is no hardcoded positive keyword list or bonus for particular document terms. Show at most 30 words, all found in the document. Retain a manual word entry for missed terms. Suggestions and recognized text live only for the active session.
- Offer `-` and `_` as separator choices initially; default to `-`. When the user appends a chip after the first, capture the **currently selected** separator before that new part. Changing the separator later affects only future additions. Example: select Date, add Acme with `-`, switch to `_`, add Invoice → `2026-10-05-Acme_Invoice.pdf`.
- Removing a part removes its preceding separator. If the first part is removed, the next part becomes first without a leading separator. Re-adding a removed chip appends it at the end using the then-current separator.
- A direct edit to the complete filename takes precedence over the composed suggestion. To keep chip state honest, direct editing converts the current stem into one custom part and clears chip-selection indicators; Undo restores the immediately preceding composition. Later chip taps append to the custom part using the active separator.
- Add `.pdf` automatically and validate the resulting filename before export. A valid user-confirmed name is required, but no chip selection is mandatory.

## Constraints and safeguards

- Never modify an original, overwrite a destination file, or retain a persistent PDF library. Keep the one unfinished app document and its draft filename in protected, backup-excluded temporary storage across app restarts; clean them after export or discard and reclaim other abandoned sessions safely. If iOS evicts the temporary cache, explain that recovery is unavailable.
- Process on-device without an account or backend. Recompute OCR and suggestions when restoring an unfinished session. Do not persist recognized text, ranked candidates, completed-document history, or word ratings.
- Preserve existing bounded import/OCR limits until deliberately revised. Encrypted or unreadable input remains rejected. Scan classification is deliberately conservative; uncertainty preserves the existing PDF text. Replacing a scan OCR layer rasterizes the already scanned page in the temporary result, with bounded high-resolution rendering. If changing a PDF would damage annotations, forms, or signatures, keep the readable copy available for naming/export and explain the OCR limitation.
- Keep light/dark support, the light/dark/tinted icon family, native iPhone controls, accessibility labels and non-color selection indicators. Show processing progress and permit cancellation.
- Apple Shortcuts integration remains a later milestone. iPad optimization, arbitrary Office/web conversion, cloud processing, document archive, conditional scripting, and automatic routing remain outside this redesign.

## Acceptance

The end-to-end app and share-extension journey is import → automatic OCR → preview with ranked date/word suggestions → user-composed or typed filename → explicit share/save/discard. Searchable native text survives; confidently identified old scan OCR text is replaced by Apple OCR in the copy; scans without text become searchable, and mixed pages gain only missing text. Separator changes affect future joins only. No legacy default can silently save a document. Empty or uncertain suggestions never strand the user. Source preservation, collision handling, cancellation, cleanup, and accurate errors remain regression requirements.

The user chose a short final test suite instead of per-increment tests. Run `make verify` before integrating code. Targeted iPhone verification of the full share, Files-provider, and OCR journey remains necessary before claiming device qualification; a signed Release has been installed and launched on an iPhone 14 Pro.
