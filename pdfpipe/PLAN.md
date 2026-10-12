# PDF Pipe implementation plan

Status: I1–I8 implemented and simulator-verified; I9 completed for automated simulator and targeted iPhone checks, with the evidence gaps below still open. Product requirements and decision IDs are authoritative in [PROJECT.md](PROJECT.md). This plan does not authorize publishing or deployment.

## Baseline and delivery rules

The MVP is implemented: bounded temporary import, preview, searchable OCR, persisted pipelines, legacy filename templates, interactive export, and configured-folder unattended execution. Home supports swipe deletion and pipeline-first import. The editor uses fixed OCR → Rename → Save switches; OCR can skip existing text or replace its text layer. Original preservation, safe Inbox consumption, atomic destination publication, preflight validation, and interrupted-session cleanup have regression coverage.

Implement each increment as a small coherent change with a demonstrable result. Preserve saved configuration and legacy template semantics; keep incomplete features unavailable in unattended execution. Verify every increment in the simulator first, with relevant automated and visual checks, before starting the next increment. Run focused checks during development and `make verify` before each code integration. Its unsigned device-SDK Release analysis/build remains required and does not constitute physical-iPhone verification. Update current-use documentation only when the behavior works. Keep PROJECT.md requirements, ARCHITECTURE.md implementation ownership, and this checklist synchronized. Root direct-to-main Git policy applies; do not mix unrelated changes.

Recommended sequence: **I1 → I2 → I3 → I4 → I5 → I6 → I7 → I8 → I9**. I1/I2 are independent of the naming work. I8 is the final functional increment; I9 is the final validation phase. Physical-iPhone checks occur only after I8 and only where needed to resolve remaining evidence gaps. Earlier increments record device-only questions and limitations without interim iPhone runs. Decision IDs mark the latest point at which a policy must be settled, not a requirement to ask every question before starting.

## I1 — Focused home screen and adaptive appearance

- [x] Remove the home icon, slogan/promotional copy, and storage-policy footer.
- [x] Retain import, pipeline creation/editing/duplication/swipe deletion, and default/unattended indicators in a concise native layout.
- [x] Centralize accent/semantic colors and check app + extension in light/dark appearances. Prepare the adaptive-blue proposal for D1; an explicit appearance setting remains optional.

**Result:** a useful, uncluttered home screen and consistent appearance across existing flows.

**Implementation area:** `PdfPipe/HomeView.swift`, `PdfPipe/PipelineEditor.swift`, `Shared/WorkbenchView.swift`, shared appearance resources as needed. If a manual override is selected, persist it without document data and apply it consistently in app and extension.

**Acceptance:** visual review of Home, editor, workbench, errors, and controls in both modes; readable contrast, large text, and non-color selection/default indicators. Existing import-first-pipeline and swipe-deletion UI checks still pass. Do not add tests that merely assert decorative copy is absent.

**Dependency/decision:** none; D1 is settled from the visual comparison before final color acceptance.

## I2 — Light, dark, and tinted icon family

- [x] Derive three coherent appearances from the selected v1 motif; preserve its identity.
- [x] Integrate the assets through the project-owned icon workflow and retain reproducible source assets.
- [ ] Verify the actual Home Screen icon variants, including different user-selected tints and small display sizes.

**Result:** PDF Pipe fits the user's Home Screen appearance without changing its recognizable motif.

**Implementation area:** `design/`, `PdfPipe/Assets.xcassets/`, and `project.yml` only if generation settings need to change. This is separate from app-interface color preference.

**Acceptance:** visual comparison of all variants in the simulator, valid asset/build output, no unintended opaque panels or lost foreground detail in tinted appearance. Record any simulator limitation; physical icon checks, if needed, occur only in I9 after I8.

**Dependency:** no naming dependency; align with the I1 visual direction where appropriate.

## I3 — Naming foundation and staged processing

- [x] Separate template syntax/configuration validation from document-value resolution and final filename validation.
- [x] Introduce a shared typed representation of template parts/resolution state while keeping saved legacy templates lossless and preserving `{date}` as processing date.
- [x] Capture a stable processing timestamp for each new naming run so preview and export cannot diverge at midnight. Reuse it while reviewing/editing that run.
- [x] Add session-scoped analysis state and a processing boundary after OCR, before final rename/save. Cancellation, retry, and cleanup must own the intermediate copy correctly.
- [x] Keep the current user workflow operational; do not expose unsupported new tokens yet.

**Result:** existing pipelines behave as before, and naming can wait for content without blocking OCR or rerunning it for each filename edit.

**Implementation area:** `Shared/Pipeline.swift`, `Shared/DocumentEngine.swift`, `Shared/DocumentSessionModel.swift`; extract small shared naming types/services where useful. The current engine computes a final name before OCR, and the workbench preview assumes all values already exist—both assumptions must change together.

**Acceptance:** old configuration fixtures decode/round-trip without token/literal changes; old preview/execution outputs agree; unknown syntax remains an error; unresolved content is distinguishable from an invalid template. Test cancellation at the new boundary, repeated runs without stale analysis, source preservation, and stable time across preview/export. The existing workflow passes the integration gate.

**Dependency:** independent of I1/I2; prerequisite for all content-derived naming.

## I4 — Document date with processing-date fallback

- [x] Read available text after the enabled OCR step or from an existing searchable PDF; retain enough page/context information to explain candidate dates.
- [x] Resolve a document date under the agreed D2 policy, with processing date only when no document date is found.
- [x] Expose the result and its source in the interactive workbench; expose uncertainty/candidates rather than a fabricated final date.
- [x] Make the new date value available to the shared template resolver while retaining old `{date}` semantics. Keep unattended use unavailable until I8.

**Result:** an interactive import can use a content date and clearly show when the fallback was used.

**Implementation area:** a bounded shared text-analysis/date component, engine/session state, and workbench naming feedback. Do not use file metadata as fallback. Analysis must remain on-device and off the UI actor.

**Acceptance:** synthetic fixtures for labeled document versus due dates, repeated identical dates, multiple different dates, ambiguous day/month order, invalid/leap dates, no date, and OCR noise. Verify calendar dates do not shift due to timezone conversion; missing and ambiguous states remain distinct. Text-only PDFs and OCR-produced text follow the same resolver. User-visible behavior matches D2.

**Dependency/decision:** I3; D2 before date acceptance. Language/format support must be stated and tested, not inferred from one sample.

## I5 — Significant-word ranking

- [x] Implement a deterministic, bounded ranking strategy against the language/document scope selected in D5.
- [x] Filter stopwords and repeated boilerplate; normalize/deduplicate candidates while retaining suitable display text. Use relevance signals beyond raw frequency and stable tie-breaks.
- [x] Supply ordered candidates and significance weights for Word 1–3 and the later cloud; do not persist recognized text or candidates in settings/logs.
- [x] Surface missing text/too few meaningful candidates according to D3. Never run disabled OCR implicitly.

**Result:** the shared analysis can produce inspectable, ranked naming suggestions from representative documents.

**Implementation area:** shared text-analysis/ranking component and synthetic test fixtures. Prefer platform capabilities or a small local algorithm; no new backend or runtime dependency without demonstrated need.

**Acceptance:** curated fixtures cover headings versus repeated footer text, German/English if selected, capitalization/inflection, punctuation/numbers, repeated words, OCR noise, multilingual or unsupported text, empty text, and ties. Verify top results against expected useful concepts, not only the scoring formula. Record ranking limitations and measure resource use at supported document limits.

**Dependency/decisions:** I3 and reusable text extraction from I4; D3/D5 before ranking acceptance. Phrase support is deferred unless explicitly selected.

## I6 — Chip-based filename template editor

- [x] Replace primary raw-template entry with tappable date, Word 1–3, `_`, and `-` chips; support removing/replacing parts. Drag reordering is optional, not a prerequisite.
- [x] Preserve editing of existing original-name, processing-date, manual-text, and literal parts. Distinguish document-date-with-fallback from processing-date-only in labels.
- [x] Show clearly labeled example values in the pipeline editor and actual resolved values in the document workbench, with `.pdf` automatic.
- [x] Persist the template losslessly through the shared parser/serializer; keep preview and export on the same rendering path. New ranked templates remain interactive-only until I8.

**Result:** users can compose `Date_Word1_Word2_Word3` without typing syntax, save it, reopen it, and see the correct resolved filename for a document.

**Implementation area:** `PdfPipe/PipelineEditor.swift`, reusable chip view, shared template types, workbench preview. A structured UI does not require an incompatible configuration rewrite.

**Acceptance:** unit tests for parse/serialize/render compatibility, literals containing token-like text, repeated separators, Unicode, invalid/overlong filenames, and unresolved values. Focused UI test builds and edits a template, saves/reopens it, and verifies its preview. Visually check chip wrapping, accessibility labels, large text, and light/dark selection states.

**Dependency:** I3–I5. Strictly distinguish sample preview from actual document results.

## I7 — Interactive weighted word cloud

- [x] Present the ranked candidates after text analysis, with visible weight and accessible selectable controls; include explicit selected-state indicators.
- [x] Select/deselect one or more words and update the date-prefixed filename live under the agreed D4 rule.
- [x] Show date provenance/fallback, allow correction of unresolved naming inputs, and retain final filename correction before export.
- [x] Pause before final rename/save; changing selection only recomputes the name, not OCR. Keep all selections within the current temporary session.

**Result:** import → process/analyze → choose meaningful words → review final name → share/save/discard works end to end.

**Implementation area:** `Shared/WorkbenchView.swift`, `Shared/DocumentSessionModel.swift`, shared cloud/selection view. Use the same interaction in app and share extension.

**Acceptance:** UI flow for multi-selection/deselection, date fallback, unresolved dates, no meaningful words, and final name export. Verify deterministic selection order under D4, no save before confirmation, no duplicate OCR, VoiceOver/large-text usability, preserved result after export cancellation, and cleanup after discard. Existing legacy pipelines still work without requiring word selection.

**Dependency/decision:** I4–I6; D4 before implementing selection/template overrides.

## I8 — Unattended document-derived naming and save

- [x] Enable the new date/ranked-word templates for unattended pipelines once their inputs can resolve automatically.
- [x] Resolve exactly the required rank slots; use the accepted missing-date fallback and agreed ambiguous-date/missing-word behavior.
- [x] Save only after final filename validation using the existing coordinated, exclusive publication path. Preserve destination errors, cancellation, collision behavior, and cleanup.
- [x] Keep per-import manual input incompatible with unattended execution and prevent a hidden interactive word-cloud dependency.

**Result:** sharing a document to the default pipeline produces the intended file in its configured folder without any input on success.

**Implementation area:** pipeline validation, session orchestration, engine naming boundary, and extension integration. Reuse `DestinationWriter`; do not introduce a durable job queue.

**Acceptance:** simulator session/integration tests for successful automatic naming/save, no-date fallback, competing dates, insufficient words, unavailable text, invalid destination, collision, cancellation, and cleanup. Failures never publish a partial or misleadingly named final PDF. An actual share-extension UI check in the simulator distinguishes automatic success from actionable failure.

**Dependency/decisions:** I3–I7; D2–D5 settled and tested before enabling the feature. I7 precedes this increment so the interactive correction path is already available.

## I9 — Final simulator validation and targeted iPhone checks if needed

- [x] After I8, run the final simulator `make verify` gate and `make test-release` and review the complete interactive/unattended flows.
- [x] Assess recorded evidence gaps and document whether physical-iPhone verification is needed and which checks require it. Do not schedule an automatic full device-suite rerun without a relevant gap.
- [ ] Verify app and extension imports from Files and available host apps using synthetic searchable/scanned/mixed PDFs and images, starting in the simulator.
- [ ] Assess persisted folder access across app/extension, iCloud and available third-party providers, revoked/unavailable access, successful/error/canceled saves, and collisions. Perform device-specific checks only where needed after I8.
- [ ] Exercise supported-size documents, OCR/ranking quality, cancellation/termination, cleanup, and settings/log privacy in the simulator. Use a physical iPhone after I8 where necessary to establish actual extension memory/time, locking, or provider behavior.
- [ ] Review light/dark screens, word cloud/chips, icon appearances, and configuration compatibility in the simulator; add targeted iPhone checks only for remaining gaps.
- [x] Update README/ARCHITECTURE/PROJECT with actual delivered behavior, limits, and verification evidence. List any failed or unperformed required checks explicitly.

**Result:** simulator evidence for the complete interactive/unattended workflow, supplemented by necessary physical-iPhone checks after all functional increments, with accurate remaining limits. Distribution is a separate decision and is not implied by passing this phase.

**Acceptance:** all checks above have recorded outcomes; required simulator checks pass. Each physical-iPhone check is either performed with a recorded result or marked unnecessary with its rationale. An unperformed necessary provider/resource check remains open and cannot be reported as verified. The documentation distinguishes simulator evidence, physical-device evidence, and remaining limitations.

**Dependency:** I1–I8 completed and verified in the simulator. No physical-iPhone verification before I8. Use established signing and project commands; do not assume past provisioning authorization covers unrelated changes.

## Recorded verification (2026-10-12)

| Check | Evidence and limit |
| --- | --- |
| Increment simulator checks | I1 light/dark Home screenshots and two UI tests; I2 three compiled asset renditions; I3–I5 focused unit tests including real PDF; I6/I7 chip/word-cloud UI test and visual review; I8 focused unattended unit tests. |
| Final simulator integration gate | `make verify` on iOS 27: 41 unit tests, three UI tests, static analysis, optimized unsigned device Release build. |
| Optimized simulator tests | `make test-release`: 41 unit tests passed on iOS 27. |
| Physical targeted tests | iPhone 14 Pro, iOS 27.0.1: 23 tests covering date/ranking, real-PDF/OCR processing, and unattended local saving. No full UI suite was rerun on device. |
| Latest physical install | Signed optimized Release 0.1.0 (build 1), analysis/build and signature verification passed; installed and launched as PDF Pipe after the device tests. |
| Real Inbox/cleanup | Actual Inbox delivery previewed and consumed; relaunch reclaimed abandoned session. Backup exclusion belongs on Documents because iOS forbids modifying Inbox itself. |
| Export integrity | Local destination tests cover atomic publication/collisions/errors/cancellation; a termination probe confirmed no partial final PDF. This does not prove all Files-provider bookmarks or rename capabilities. |
| Signing/App Group | User-selected team `QQ2W7FVVXM` preserved; signed installation/shared configuration verified. Automatic provisioning was explicitly authorized for the preceding device-test run. |

The interactive chip and word-cloud path was exercised in a simulator UI test. The unattended success/failure path was exercised in simulator and device session tests against a local destination; the new unattended share-extension-to-external-provider path has not been exercised end to end. The simulator compiled the light/dark/tinted icon renditions, and the default Home Screen icon was viewed; switching the Home Screen appearance/tint was blocked by the locked Mac GUI. The actual appearance of the dark/tinted icons remains unverified. iCloud and third-party Files-provider bookmarks, revoked access, extension memory/time under large OCR workloads, and interrupted provider writes require targeted real-device checks with a user-selected destination. No guaranteed background completion or distribution readiness is claimed.

## Deferred work

Apple Shortcuts integration follows as a separate planned capability; actions and ordering relative to release remain TBD. Other unselected ideas and scope boundaries remain in PROJECT.md.
