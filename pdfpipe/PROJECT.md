# PdfPipe

Workflow: ESTABLISHED
Maturity: MVP

## Product concept

PdfPipe is a small, native iPhone app that receives a document, processes a temporary copy through a saved pipeline, and exports the resulting PDF. It supports interactive review and unattended processing with automatic saving to a configured folder. Originals are never modified.

The app stores pipelines and configuration, not a document library. Document-derived filename generation is a core planned capability. iPad support and Apple Shortcuts integration are deferred.

Selected app icon: [design/app-icon-v1.png](design/app-icon-v1.png), the first version with the curved turquoise pipeline arrow. Use this asset for app integration; v2 is an unselected alternative. The selected PNG is 1024×1024 and opaque; its generation prompt is saved alongside it.

This document is the authoritative product concept and current state. The first MVP is implemented in a self-contained app/share-extension project. Simulator verification passes; physical-device feasibility and distribution are not yet established.

Platform policy: iPhone on iOS 26 or later. Build with Xcode 27 and XcodeGen. Use `make help`, regenerate with `make generate`, and run `make verify` before code integration. See [README.md](README.md) for usage/limits and [ARCHITECTURE.md](ARCHITECTURE.md) for implementation ownership. Root direct-to-main Git policy applies; preserve unrelated project changes.

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

The standalone app manages pipelines and imports documents from Files using the same engine. Direct app import starts interactively even when an unattended default is configured.

MVP interaction details:

- Show pipeline steps and the proposed filename before an explicit Run action in interactive mode.
- Show progress and allow cancellation; allow final filename correction before export.
- Keep the active result available after an export cancellation.
- Stop on a failed processing step and allow retry from the session input. A destination-write failure keeps the active processed result available for another export.
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

The minimum iOS version is settled at iOS 26. If extension limits conflict with unattended processing, present the evidence and decide a revised workflow; do not silently add persistent job storage or assume the extension can launch the app.

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

## Verification status (2026-10-11)

- `make verify` passes on iOS 26.0 and 27.0 simulators: 20 unit tests and one end-to-end UI test. The final reviewed implementation passes the iOS 27 gate.
- `make build-device` passes for the app and share extension against the iOS 27 device SDK, without signing/provisioning.
- Simulator screenshots were visually reviewed. The share-sheet test invokes the actual extension, verifies supplied filename preservation, and checks that extension discard retains the host's export copy.
- Physical-device signing/App Group setup and real provider/resource validation remain required. A connected iPhone is available; signing-team information is pending. See [PLAN.md](PLAN.md) for the outstanding gate.

## Open decisions

- Intended audience, distribution, and monetization.
- Physical-device OCR language availability and quality. MVP automatically detects language and skips pages with existing text; mixed text/image pages may retain unrecognized content.
- Additional template/date formatting options. MVP uses {original}, {date} (local yyyy-MM-dd), and {text}; creates unique names on collision; rejects unknown tokens and hidden/empty/overlong names.
- Supported extraction fields/categories, extraction approach, and missing-value fallbacks.
- Interactive entry point when a default unattended pipeline is configured; no manual-override feature has been separately accepted.
- Physical-device resource/conversion validation. MVP limits inputs to 30 MB/50 pages, images to 40 million pixels, and OCR rasterization to 4 million pixels per page. Encrypted PDFs are rejected on import; annotated/form PDFs are rejected for OCR. Signatures are not validated; signed PDFs are unsupported for OCR.
- Extension export/access behavior, error presentation, cleanup mechanics, and exact save semantics.
- Signing team/App Group registration for physical-device checks and distribution.

## Scope boundaries

No initial batch processing, arbitrary Office/web conversion, conditional scripting, AI classification, content-based destination routing, cloud processing, signing, annotation, document archive, or recoverable background queue.

Unselected suggestions are not requirements: pipeline testing UI, configurable extraction rules, configurable fallback rules, image preparation, page operations, compression presets, pipeline export/import, and a manual override feature. Filename templates are accepted; Shortcuts is accepted for later.

## Platform references

- [Apple: App extension overview](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionOverview.html): extension lifecycle and restrictions on opening the containing app.
- [Apple: Handling common extension scenarios](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html): extension resource constraints and shared-container access.
- [Apple: Recognizing text in images](https://developer.apple.com/documentation/vision/recognizing-text-in-images): text recognition; writing a searchable PDF requires separate implementation and validation.
- [Apple: Providing access to directories](https://developer.apple.com/documentation/uikit/providing-access-to-directories): selected folders, saved access, coordinated writes, and revoked permissions. Access across app/extension must be proven.
