# PDF Pipe implementation plan

Status: **planned, not implemented**. [PROJECT.md](PROJECT.md) is the target product source of truth. [README.md](README.md) and [ARCHITECTURE.md](ARCHITECTURE.md) describe the current MVP until the redesign lands. This plan does not authorize distribution or deployment.

## Delivery rules

Work in the order below. Each increment must leave the app buildable and the original-safe session path coherent. Use focused tests while developing, then verify the increment in an iOS simulator before starting the next. Run `make verify` before each code integration; it includes unit/UI tests, static analysis, and an optimized device-SDK Release build. Device-SDK compilation is not iPhone verification. Test on an iPhone only after the last functional increment if simulator evidence cannot establish provider, signing, resource, or interaction behavior. Keep README current-use instructions synchronized only with shipped behavior.

## I0 — Baseline and safe migration boundary

- [ ] Record the current simulator baseline and characterize existing OCR and naming behavior before changing it.
- [ ] Add single-flow preferences without deleting or rewriting `pipelines.v1`. Define how a sole or explicit-default destination can seed a one-tap save choice; require user choice when several destinations compete.
- [ ] Ensure no old unattended default can execute once the new flow is active. Add migration/compatibility tests for one, many, corrupt, and absent legacy configurations.

**Acceptance:** existing documents and settings remain safe, old data can be recovered, and a new import cannot silently save through an old default. Verify in the simulator.

## I1 — Automatic, non-destructive OCR

- [ ] Start OCR from every import, including text-bearing PDFs, with progress and cancellation; keep the original and existing embedded text intact.
- [ ] Add OCR text only where selectable text is missing. For mixed pages, compare recognition regions with existing text coverage and avoid duplicate searchable text. Do not rasterize and replace an existing text layer.
- [ ] Preserve a readable preview/manual naming path when OCR cannot add text, including annotated/form/signed PDFs where re-emission is unsafe; show a specific limitation.
- [ ] Cover image-only, text-only, mixed single-page, rotated, multilingual/noisy, failed, and canceled cases, including text extraction, selection, visible appearance, and source bytes.

**Acceptance:** OCR is attempted automatically; existing text remains selectable and unchanged; newly recognized image text becomes searchable where supported. The simulator tests prove mixed-page behavior, not merely separate text and scan pages.

## I2 — Session naming model

- [ ] Produce ranked date candidates and significance-ordered word candidates after OCR without storing content persistently.
- [ ] Represent the filename as ordered parts with the separator captured at each append. Implement remove/re-add, processing-date fallback, manual word, live filename validation, automatic `.pdf`, and a direct custom-name mode with Undo.
- [ ] Keep analysis and selections session-scoped. Changing a name or separator must not rerun OCR.
- [ ] Test tap order, separator switching, deletion of first/middle parts, custom edits followed by chips, empty/ambiguous suggestions, Unicode, and invalid/long filenames.

**Acceptance:** one pure naming model produces the same preview and export name; previous joins never change when the active separator changes. Verify model and a small UI harness in the simulator.

## I3 — One-flow iPhone and share UI

- [ ] Replace the home pipeline list and chooser with a clear import action and single-flow settings. File opening leads immediately to progress, then to one preview-and-naming screen.
- [ ] Show a scrollable PDF preview, OCR status, date chips with an accessible suggested-date marker, and a weighted word cloud ordered by significance.
- [ ] Show selected order, `-`/`_` control, live editable filename, manual entry, clear errors, and explicit share/save/discard actions. Keep light/dark, large text, VoiceOver, and non-color selection indicators usable.
- [ ] Apply the same interaction to app import and share extension. UI tests cover scanned, searchable, mixed, no-word, and cancellation journeys.

**Acceptance:** a user can open a file and complete content-based renaming quickly without seeing a pipeline or Run button. No naming/export choice happens automatically. Verify interactions and visual states in the simulator.

## I4 — Export, cleanup, and legacy removal

- [ ] Connect the chosen name to the existing safe share/Files/configured-folder writers. A configured folder is a user-triggered action only.
- [ ] Remove obsolete pipeline/template/unattended UI and execution paths after I0 migration tests prove safety. Keep legacy data inert for recovery; do not remove it as a cleanup shortcut.
- [ ] Verify collisions, provider errors, canceled sheets, retry, session cleanup, source bytes, and absence of persisted recognized content.

**Acceptance:** the only output is explicitly user-directed, final filenames match the live preview, and no legacy default can run. Verify in the simulator and pass `make verify`.

## I5 — Final qualification

- [ ] Run the complete simulator integration gate, optimized-code tests where relevant, and visual/accessibility review in light/dark and large text.
- [ ] Exercise representative real scanned, searchable, and mixed PDFs within supported bounds; record recognition quality and resource limits honestly.
- [ ] Perform targeted iPhone checks only for unresolved device-specific evidence, after I4: share extension, Files providers/bookmarks, OCR memory/time, and the final user journey.
- [ ] Update README, ARCHITECTURE, and PROJECT to match delivered behavior; record any open limitations.

**Acceptance:** every required check has a recorded pass or explicit outstanding limit. No claim of device or provider support rests solely on simulator evidence.
