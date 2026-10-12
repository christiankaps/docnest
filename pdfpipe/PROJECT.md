# PDF Pipe

Workflow: ESTABLISHED
Maturity: MVP

## Purpose and sources of truth

PDF Pipe is a native iPhone document workbench. It receives one document, processes a temporary copy through a saved pipeline, and lets the user share or save the resulting PDF. An explicitly configured default pipeline can process and save unattended. Originals are never modified.

This file owns the consolidated product concept, accepted requirements, and open product decisions. [PLAN.md](PLAN.md) owns delivery increments and verification status; [ARCHITECTURE.md](ARCHITECTURE.md) describes the implemented architecture; [README.md](README.md) describes current usage, commands, and limits. Planned behavior below must not be presented as already implemented.

Platform: iPhone first, iOS 26 or later; build with Xcode 27 and XcodeGen. The display name is **PDF Pipe**. Preserve existing bundle IDs, App Group, project paths, targets/schemes, installation, and saved configuration. Root direct-to-main Git policy applies. Use `make help`, edit `project.yml` and regenerate, and run `make verify` before code integration.

## Current baseline

The first MVP implements PDF/JPEG/PNG import, preview and attributes, optional searchable OCR, simple filename templates, pipeline management, interactive export, and configured-folder unattended saving. The editor shows OCR, Rename, and Save once each with enable switches and fixed execution order. Home supports swipe deletion and pipeline-first import.

Current templates accept `{original}`, `{date}` (local processing date, `yyyy-MM-dd`), `{text}` (per-import manual input), and literals. The editor is a plain text field. Document-date extraction, significant-word ranking, word-cloud selection, and template chips are not implemented.

Current UI uses system surfaces with hard-coded teal accents and retains home-screen branding/footer copy. Only one explicit app-icon asset is integrated. Deliberate light/dark visual verification and dark/tinted icon assets remain pending.

The latest simulator gate passed 33 unit tests, two UI tests, and optimized unsigned device Release analysis/build. The preceding physical-iPhone baseline passed 27 unit tests and one UI test; the latest signed Release is installed and launch-checked. Provider/resource feasibility and distribution are not yet established. Exact coverage and remaining checks are in PLAN.md.

## Product invariants and scope

- One document per session, received through the share sheet or Files import. Accept PDF, JPEG, and PNG; each imported image becomes one PDF page. Other conversions and batch processing are outside this milestone.
- Show preview and attributes: filename, format, byte size, page count, page dimensions, and text availability.
- Persist pipelines, preferences, and destination access references; never create a persistent document library or retain recognized content in settings or logs.
- Process on-device without an account or backend. A user-selected cloud-backed destination is an export location, not cloud processing by PDF Pipe.
- Never overwrite an original or an existing destination file. Collisions create a unique filename.
- Temporary working copies are isolated and excluded from backup. Clean up on completion/discard and reclaim abandoned sessions at the next safe opportunity; preserve active export consumers.
- No document history, interrupted-session recovery, or durable retry queue. iOS termination can interrupt execution and defer cleanup. Completed provider writing does not guarantee completed cloud synchronization.
- Keep current bounded import/OCR limits and rejection rules described in README.md until separately changed. Encrypted PDFs are rejected; OCR does not support annotated/form/signed PDFs. Signatures are not validated.

## Pipeline model

A pipeline has a name, enabled steps, optional save destination, filename template, and execution mode. Users create, edit, duplicate, and delete pipelines. Every editor shows the same steps in the fixed order **OCR → Rename → Save to folder**. Each enabled step runs once; there is no user-controlled step reordering.

OCR defaults to skipping pages with existing text; scanned pages in mixed PDFs are still recognized. Disabling that option replaces existing text layers with fresh OCR. A mixed text/image page can retain unrecognized image content when skipping is enabled; the interface must describe this limit truthfully.

Document analysis belongs to Rename and supplies its date and word values after any enabled OCR. It is not a new reorderable step. Existing searchable text can supply naming values without rerunning OCR. Text-dependent renaming must not silently turn a disabled OCR step on; handling unavailable text is covered by the missing-value policy below.

Save to folder is optional and always last. Disabling Save also clears unattended/default settings. Unattended pipelines require a destination and no per-import manual input. Users explicitly designate the default for shared imports; last-used is never an implicit default. Invalid defaults produce a chooser or actionable error, never silent substitution.

## User journeys

**Direct app import:** choose Import → select a pipeline → select a file → review/process. This remains interactive even when an unattended default exists.

**Interactive shared import:** share to PDF Pipe → select a pipeline → inspect/process the temporary copy → for content-derived naming, review date and choose significant words → review filename/result → share, save, or discard. The naming interaction occurs after text is available and before any final save. OCR must not need to run again merely because the user changes the selected words.

**Unattended shared import:** share to PDF Pipe → run the explicit default → OCR if enabled → resolve document date and ranked-word template → save to the configured folder → clean up. A successful run requires no word selection or other confirmation.

In every mode, show progress and permit cancellation. An export cancellation keeps the result available. Processing errors support correction/retry or discard; destination-write errors keep the processed result available for another export. Do not silently redirect output. Existing pipeline selection, deletion, configuration persistence, and source preservation remain regression requirements.

## Document-derived naming: accepted next milestone

### Date

Prefer a date found in the document content. If none is found, use the processing date. File metadata is not the intended fallback. Document date and processing date remain distinct concepts: existing `{date}` templates keep their current meaning.

Multiple plausible dates, ambiguous numeric formats, and low-quality recognition need an explicit selection policy before unattended document-date naming ships. Do not silently call an ambiguous result “no date” to bypass that policy.

### Words and interactive selection

After OCR, or using existing text, show a word cloud weighted by each word's importance/significance in the document. Users select one or more words to form the suffix after the date. Word 1, Word 2, and Word 3 in automatic templates mean the first, second, and third highest-ranked significant words, respectively.

Frequency alone is not the product definition of significance. The ranking method and supported language coverage require representative-document evaluation before being declared adequate. Short phrases, manually added cloud terms, and user-controlled ordering of selected words are proposals awaiting a scope decision.

### Template editor

Use tappable chips for **Date**, **Word 1**, **Word 2**, **Word 3**, and common separators **`_`** and **`-`**. Show the assembled template and a live filename preview; `.pdf` is added automatically. The user should not need to type token syntax.

Example template: `[Date] [_] [Word 1] [_] [Word 2] [_] [Word 3]`.
Example result: `2026-10-05_Telekom_Rechnung_Internet.pdf`.

In the pipeline editor, no document is loaded: previews must clearly use example values. With a document loaded, the preview must use actual resolved values and expose unresolved inputs. Existing original-name, processing-date, manual-text, and literal templates must remain readable/editable without silently changing meaning. Exact new token syntax and storage representation are implementation choices, not user-facing syntax requirements.

### Resolution and failure behavior

Use the same naming rules for preview and execution. Check template structure/configuration before OCR; resolve content-dependent values and validate the final filename once text is available. Do not prevent analysis merely because its output does not exist yet, and do not show an invented final name beforehand.

Missing or ambiguous required values require correction or an explicit failure unless an accepted fallback applies. The processing-date fallback is accepted for an absent document date. Missing words have no accepted fallback yet. Unattended execution must not export a filename that silently omits required values or substitutes invented words.

Interactive word selection must never leak into persisted pipeline configuration. The choice of how an interactive selection overrides an automatic ranked-word template remains open (D4 below).

## Appearance and home screen: accepted next milestone

- Support light and dark appearances throughout the app and share-extension workflow, including word clouds, chips, previews, dialogs, and errors.
- Provide light/default, dark, and tinted app-icon appearances using the selected [v1 motif](design/app-icon-v1.png), the curved pipeline arrow. V2 remains unselected. Icon appearance follows the user's Home Screen setting independently of app-interface appearance.
- Remove the large app icon, slogan, accompanying promotional copy, and “No document library” footer from Home. This does not change the temporary-storage policy.
- Focus Home on importing and managing pipelines, retaining swipe deletion and visible default/unattended status.
- Reconsider the current teal accent. No replacement color has been selected.

Recommended visual direction, not yet approved: PDF Pipe navigation title → import action → Pipelines heading with add action → concise pipeline rows. Use neutral system surfaces and restrained adaptive blue for actions/selected controls. Selection should also have a checkmark or equivalent non-color indicator. Follow system appearance by default; an explicit System / Light / Dark setting is optional pending D1.

The icon family must remain recognizable at Home Screen size and with different user tints. Validate contrast and legibility in both interface appearances. [Apple's icon guidance](https://developer.apple.com/design/human-interface-guidelines/app-icons) describes system-controlled icon appearances.

## Open decisions for the next milestone

These are proposals for the relevant increment, not reasons to block unrelated work.

| ID | Decision | Recommendation to evaluate | Needed before |
| --- | --- | --- | --- |
| D1 | Accent and appearance control | Preview adaptive blue in light/dark; system-following initially, explicit override only if wanted. | Final appearance acceptance (I1). |
| D2 | Competing/ambiguous dates | Prefer clearly labeled document/issue dates over due/service dates; show candidates interactively; fail unattended when unresolved. Start with existing `yyyy-MM-dd` output. | Date behavior acceptance (I4), unattended enablement (I8). |
| D3 | Too few significant words or no usable text | Keep strict missing-value behavior: explain/correct interactively, fail unattended. Do not silently omit requested word slots or enable OCR. | Ranked-word acceptance (I5), unattended enablement (I8). |
| D4 | Interactive selection versus ranked template | Keep automatic rank slots stable; let explicit cloud selection build a session-only date + selected-word suffix in selection order. No automatic saving before confirmation. | Word-cloud interaction (I7). |
| D5 | Ranking scope and quality | Start with a deterministic on-device approach; evaluate German/English synthetic fixtures, filter stopwords/boilerplate, consider headings/distinctiveness, deduplicate, use stable tie-breaks. Defer phrases initially. | Ranking acceptance (I5). |

Additional future decisions: distribution, monetization/audience, supported extraction categories beyond date/words, configurable date formats, and a manual override entry point for an unattended default. Physical OCR language quality, provider access, and extension resource behavior require evidence, not assumed guarantees.

## Acceptance and boundaries

Every completed increment must preserve original bytes, pipeline/default behavior, configuration compatibility, cancellation, collision handling, and truthful save errors. New acceptance checks must cover date fallback/ambiguity, ranked words, template equivalence, actual filename previews, interactive selection before save, and unattended no-input success. Appearance changes require visual review in both modes and accessible selection indicators.

Verify each increment in the simulator first, including relevant automated and visual checks, before proceeding to the next increment. Physical-iPhone verification, if needed to resolve evidence gaps, occurs only after the final functional increment (I8). Record device-only questions during earlier increments without scheduling interim iPhone runs. The existing `make verify` gate, including unsigned device-SDK Release analysis/build, remains required; compilation for the device SDK is not physical-device verification. See PLAN.md for increment-specific checks and the final validation phase.

Apple Shortcuts is accepted for later; exact actions are TBD. iPad, arbitrary Office/web conversion, conditional scripting, AI classification, content-based destination routing, cloud processing, signing, annotation, a document archive, and recoverable background jobs remain out of scope.

Unselected ideas remain proposals: configurable extraction/fallback rules, page regions/patterns, image preparation, page operations, compression presets, pipeline export/import, and a pipeline testing UI. Do not introduce them implicitly while implementing chips or extraction.

## Platform references

- [Apple: App extension overview](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html): extension lifecycle and restrictions on opening the containing app.
- [Apple: Handling common extension scenarios](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html): extension resource constraints and shared-container access.
- [Apple: Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images): recognition; writing a searchable PDF still requires separate implementation and validation.
- [Apple: Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories): selected folders, saved access, coordinated writes, and revoked permissions. Cross-process provider access must be proven.
