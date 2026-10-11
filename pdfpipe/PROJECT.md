# PdfPipe

Workflow: INITIALIZING
Maturity: CONCEPTION

## Product concept

PdfPipe is a small, native iPhone app that receives a document, processes a temporary copy through a saved pipeline, and exports the resulting PDF. It supports interactive review and unattended processing with automatic saving to a configured folder. Originals are never modified.

The app stores pipelines and configuration, not a document library. Document-derived filename generation is a core planned capability. iPad support and Apple Shortcuts integration are deferred.

This document is the authoritative concept. Accepted scope is distinguished below from recommended interaction details and unresolved decisions. No app implementation or platform feasibility is claimed yet.

## Accepted first-version scope

- iPhone first; one document per session.
- Receive PDFs through the iOS share sheet; accept JPEG and PNG and convert each imported image to a PDF. Other input formats are outside the initial scope.
- Display a document preview and attributes: filename, format, byte size, page count, page dimensions, and text availability.
- Create, edit, duplicate, and delete named pipelines containing ordered processing steps and an optional final Save action.
- OCR produces searchable/selectable text in the exported PDF while preserving visible page appearance.
- Filename templates combine literal text with original basename, processing date, and user-entered text. Document-derived placeholders follow in the extraction milestone.
- Optionally configure a destination folder per pipeline.
- Support interactive result review and user-directed sharing/saving, or unattended processing and saving without further input on a successful run.
- Users explicitly designate one default pipeline for unattended imports. Without a default, show the pipeline chooser. The last-used pipeline never becomes an implicit default.
- Process on-device, without an account or backend. User-selected output folders may be cloud-backed; exporting there does not constitute cloud processing by PdfPipe.

## Pipeline model

A pipeline has a name, ordered processing steps, an optional destination folder, and an execution mode. The two modes are interactive review and unattended execution; their exact settings UI is TBD.

Initial steps are OCR and template-based renaming. Saving, when configured, is the final action. The later extraction capability supplies document-derived values to filename templates before renaming.

An unattended pipeline requires a configured destination and no per-import manual input. An invalid or unavailable default must lead to a chooser or actionable configuration error, not silent execution of a different pipeline.

Illustrative initial pipeline: OCR → rename using processing date and original basename → save to a configured folder.

Illustrative later pipeline: OCR if needed → extract document date, sender, and invoice number → rename using those fields → save. These fields are examples; supported fields and document categories remain TBD.

## User journeys

Interactive: share a document to PdfPipe → choose a pipeline → inspect/process the copy → review the resulting PDF and filename → share, save, or discard.

Unattended: share a document to PdfPipe → run the explicitly configured default pipeline → save to its configured folder → clean up temporary files. No further interaction is needed on a successful run.

The standalone app manages pipelines and their configuration. Recommended addition: import from Files directly in the app, using the same processing flow.

Recommended interaction details, not separately accepted scope:

- Show pipeline steps and the proposed filename before an explicit Run action in interactive mode.
- Show progress and allow cancellation; allow final filename correction before export.
- Keep the active result available after an export cancellation.
- Stop on a failed processing step and allow retry from the session input.
- On filename collisions, create a unique filename rather than overwrite any existing destination file. The source must never be overwritten under any policy.
- Show destination/processing failures clearly; do not silently redirect output or report a failed save as successful.

A saved destination PDF is an intentionally persistent user-owned output. It is outside PdfPipe's temporary working storage.

## Core follow-on: document-derived renaming

Accepted workflow: OCR if needed → extract fields → build filename → review/correct and export, or save unattended when required values are unambiguous.

Missing or ambiguous required fields must prompt correction or an explicit failure. Do not invent values. Document dates and processing dates are distinct template fields.

This is a core product milestone deferred from the first MVP, not an optional extra. Exact fields, extraction method, ambiguity handling, template formatting, and fallback behavior are TBD. Configurable extraction rules using labels, patterns, or page regions have not been selected.

## Storage and privacy

Persist pipeline definitions, preferences, and destination access references. Minimal operational metadata may support temporary-file cleanup; document content and recognized text must not enter settings or logs.

Temporary disk files are allowed for processing and export. Use isolated session storage, excluded from backup. Clean up after completion/discard and remove abandoned files at the next safe opportunity. Keep export files available for as long as a system consumer needs them.

There is no document history, interrupted-session recovery, or durable retry queue. Unexpected iOS process termination can leave temporary files pending cleanup; immediate deletion cannot be guaranteed. Exact cleanup mechanics remain to be validated.

Unattended execution means no further user input on success. It does not promise continued background processing after iOS terminates the extension. Destination-provider write completion also does not guarantee completed cloud synchronization.

## Delivery milestones

1. **Feasibility gate:** prototype temporary import, preview, OCR, interactive export, configured-folder access/saving, unattended execution, cancellation, and cleanup on real iPhones. Validate the extension independently of the full app.
2. **First MVP:** deliver the accepted scope above with reproducible build and verification commands.
3. **Core extraction milestone:** deliver document-derived filename templates with review/correction and explicit handling of missing or ambiguous required fields.
4. **Later capability:** Apple Shortcuts integration. Exact placement relative to extraction and the available actions are TBD; exposing named pipelines as document-processing actions is a proposal.

Before implementation, choose the minimum iOS version. If extension limits conflict with unattended processing, present the evidence and decide a revised workflow; do not silently add persistent job storage or assume the extension can launch the app.

## Verification expectations

The concept should be validated against these outcomes; detailed checks will be established with implementation:

- Source bytes remain unchanged on success, failure, and cancellation.
- Exported OCR text is searchable/selectable in another viewer, and visible page appearance is preserved.
- Pipelines/configuration survive app restart without retaining document content.
- Interactive and unattended imports choose pipelines according to the explicit default policy.
- Configured-folder access works from the app and extension; revoked permission, unavailable providers, failed/partial writes, and filename collisions have truthful outcomes.
- Missing or ambiguous required extracted fields cannot silently produce a supposedly successful result.
- Export cancellation is distinct from completion, and temporary cleanup respects active consumers and interrupted sessions.
- Extension resource/lifecycle limits are understood on real devices. No guaranteed background completion is claimed without evidence.

## Open decisions

- Minimum iOS version; intended audience, distribution, and monetization.
- OCR languages and treatment of pages with existing text.
- Filename template syntax, date formatting, validation, and collision policy.
- Supported extraction fields/categories, extraction approach, and missing-value fallbacks.
- Interactive entry point when a default unattended pipeline is configured; no manual-override feature has been separately accepted.
- Resource limits, conversion fidelity, and encrypted, signed, or form PDF handling. Transformations may invalidate signatures.
- Extension export/access behavior, error presentation, cleanup mechanics, and exact save semantics.
- Build tools, verification commands, and PdfPipe-specific integration conventions.

## Scope boundaries

No initial batch processing, arbitrary Office/web conversion, conditional scripting, AI classification, content-based destination routing, cloud processing, signing, annotation, document archive, or recoverable background queue.

Unselected suggestions are not requirements: pipeline testing UI, configurable extraction rules, configurable fallback rules, image preparation, page operations, compression presets, pipeline export/import, and a manual override feature. Filename templates are accepted; Shortcuts is accepted for later.

## Platform references

- [Apple: App extension overview](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html): extension lifecycle and restrictions on opening the containing app.
- [Apple: Handling common extension scenarios](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html): extension resource constraints and shared-container access.
- [Apple: Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images): text recognition; writing a searchable PDF requires separate implementation and validation.
- [Apple: Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories): selected folders, saved access, coordinated writes, and revoked permissions. Access across app/extension must be proven.
