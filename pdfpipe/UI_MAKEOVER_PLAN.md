# PDF Pipe — UI makeover plan

Status: U1–U4 implemented and the U5 automated simulator gate passed (2026-10-12). U0's screen map was resolved directly in the production navigation, with simulator screenshots used for visual review. The manual evidence limits below remain open. [PROJECT.md](PROJECT.md) remains authoritative for product behavior; [PLAN.md](PLAN.md) records the completed naming increments and outstanding device evidence.

## Objective and diagnosis

Make the iPhone app feel calm, current, and native to iOS 26+ while making each next action obvious. Preserve the existing pipeline model, share extension, document privacy, saved configuration, and processing behavior.

The current Home combines an import button, pipeline management, and multiple status labels in one grouped list. The editor puts name, OCR, template construction, destination, unattended mode, and default selection into a dense form with explanatory paragraphs. The workbench stacks a large PDF preview, attributes, pipeline picker, word cloud, filename, and export buttons in one scroll view. Important actions move below the fold, and the screen does not signal which decision matters now. The template editor exposes every chip type at once; the horizontal assembly strip and grid make the naming task harder than necessary. A larger corner radius, more material panels, or a new accent color alone would not solve this.

## Design direction

- Use standard SwiftUI navigation, lists, forms, sheets, toolbars, system pickers, semantic backgrounds, Dynamic Type, and SF Symbols. Accent color marks the primary action and active selection; status also has a text or symbol label. Avoid decorative cards, glass overlays, gradients, and competing prominent buttons.
- One main purpose per screen, one clear primary action at a time. Keep destructive and secondary actions in menus or toolbars where their consequences are clear. Use plain language in the interface; move long explanations into contextual help and concise footers.
- Navigation title reflects the task: **Pipelines**, **New/Edit Pipeline**, **Review Document**, **Choose Filename**, **Result**. Do not add a tab bar: there are not multiple independent destinations, and PDF Pipe has no document library.
- The app and share extension use the same review/result components and terminology, adapted to the host sheet size. An unattended share keeps its no-input success path; failures reveal the same corrective UI.
- Keep the currently selected v1 app-icon motif and system light/dark/tinted asset policy. Icon artwork is a separate visual review and does not drive the interface layout.

## Target experience

### Home: pipelines and entry point

Use a navigation list titled **Pipelines**. A prominent but compact **Import PDF** action starts the existing pipeline-first flow. Each pipeline row shows its name and one short outcome line, for example **OCR · Date + 3 words · Save to Folder**. A subtle, explicit **Default for sharing** label appears only on the configured default. Tapping a row edits it; swipe actions offer Duplicate and Delete. The toolbar `+` creates a pipeline. With no pipelines, show one native empty state and **Create Pipeline**; avoid duplicate create buttons or a disabled import invitation. If configuration cannot load, place a single recovery message and retry action above the list.

Import presents a compact pipeline chooser with clear row selection, then Files. Do not hide the current choice in a menu or launch Files before the user knows which pipeline will run. Canceling either stage returns to Home without leaving a session.

### Pipeline editor: configuration by intent

Top: name field and a one-sentence live outcome summary. Below, three numbered but non-reorderable sections: **Recognize text**, **Name file**, **Save output**. Each section has a single on/off control and shows details only when enabled. The save section shows its chosen folder as a tappable row. A final **Shared files** section offers **Run automatically** and **Use as default** only when a valid save destination makes them meaningful; explain the dependency at the control rather than in a long paragraph. Keep Save in the navigation toolbar, with disabled or inline-error state for invalid input. A new pipeline says **New Pipeline**, not **Edit Pipeline**.

When Name file is enabled, show one composed filename row and an example. Tapping it opens a dedicated template composer instead of expanding a chip grid inside the form. The composer displays the ordered parts with large touch targets, token groups **Date**, **Words**, **Other**, and a compact separator row. Adding a part is one tap; removing/replacing a part is discoverable and announced by VoiceOver. Keep legacy `{original}`, `{date}`, `{text}`, and literal content lossless. The example is clearly labeled as an example, not a prediction for an actual document.

### Document flow: progressive stages

Use one navigation stack or a clearly staged sheet with these states:

1. **Review Document**: PDF preview takes priority; a collapsed details row reveals source name, pages, size, dimensions, and text status. Show the selected pipeline in a changeable row. Put **Run Pipeline** in a safe-area bottom action area so it remains visible without covering content. Show errors inline near the affected choice.
2. **Processing**: concise current action and progress, plus Cancel. Avoid letting controls appear tappable during a run. Keep the preview available where it helps orientation.
3. **Choose Filename** (only when review is needed): date source and any ambiguity first; then ranked suggestions as selectable, wrapping word controls. Visually vary emphasis modestly, while readable type sizes and selection checkmarks carry meaning. Show selected words in order, a manual add action, and a pinned actual filename preview. **Continue** remains visible. With an automatic template that needs no intervention, skip this screen.
4. **Result**: show the final name and a short processing summary. Use one clear primary destination action: **Save to [configured folder]** when available, otherwise **Share PDF**. Put **Share PDF** and **Save to Files** as secondary actions; keep final filename editing available. After a successful save, show a concise completion state with **Done**. A canceled export returns to Result.

The review and result UI must work from both direct import and the share extension. Pipeline-first direct import stays intact. Unattended sharing runs without review on success. On ambiguity, missing values, or save error, present a corrective state without silently changing destination or publishing a partial file.

## Visual and interaction specification

- Establish a small set of semantic styles for primary action, secondary action, grouped content, status, and document preview. Use system typography hierarchy and spacing rather than custom font sizes for ordinary text. Apply these consistently across app and extension.
- Use system background/grouped background and a single restrained accent. Verify blue in light, dark, and increased-contrast modes; adjust only if actual screens fail contrast or focus clarity. Do not use tint-colored text merely for decoration.
- Keep PDF preview aspect-correct and reveal enough of page one to recognize the document. Provide a full-preview affordance if the compact preview cannot show useful detail. The preview must not push the next required action off-screen.
- Design at narrow iPhone width and large accessibility sizes. Touch targets, chip wrapping, VoiceOver order/labels, selected state, Reduce Motion, keyboard/safe-area behavior, and error recovery are acceptance requirements.
- Copy should state outcomes: **Recognize scanned pages**, **Name from document**, **Save to folder**, **Run automatically**. Explain technical limits contextually without filling the main screen with implementation terms such as tokens or `{text}`.

## Delivery increments

Each increment starts with an app + extension screen inventory and a simulator baseline capture for the screens it changes. Implement, then inspect light/dark screenshots at standard and large text sizes, run focused UI checks, and keep prior journeys working. Use `make verify` before integration. Physical iPhone checks follow the last functional UI increment only if simulator evidence leaves a device-specific gap, matching the existing project policy.

### U0 — Design baseline and navigation prototype

- Capture current Home, empty state, editor (simple and automated pipeline), pipeline chooser, review, naming, result, and error states in simulator light/dark.
- Create a low-fidelity screen map and clickable SwiftUI preview or fixture-driven prototype for the target flow. Check a narrow iPhone width and keyboard appearance before changing production navigation.
- Record concrete before/after usability criteria: primary action visible, one decision per stage, no duplicated actions, no accidental data loss.

**Exit:** the screen map and representative target screens are reviewable; navigation and copy are internally consistent. No production behavior changes.

### U1 — Home and pipeline choice

- Rebuild Home around the pipeline list and compact Import action. Simplify row summaries, empty/error states, and toolbar actions.
- Rework the pipeline chooser as a clear selection step. Preserve edit, duplicate, swipe-delete, default indicator, pipeline-first import, and share-extension selection.

**Exit:** a first-time user can create a pipeline and import a file; a returning user can identify the sharing default and edit/delete a pipeline. Verify in simulator with UI tests and screenshots.

### U2 — Pipeline editor and template composer

- Restructure the editor into the three fixed processing sections and conditional shared-file settings. Make validation and dependency rules visible at the control.
- Move filename composition into a focused sheet, simplify token discovery, and show a persistent example. Preserve exact serialized templates and old configurations.

**Exit:** create/edit a manual and an unattended pipeline without reading long help text; reopen and reproduce the same template. Run compatibility unit tests, UI creation/edit tests, and light/dark/large-text review.

### U3 — Document review and processing

- Replace the all-in-one workbench layout with explicit review and processing states. Prioritize preview and keep the primary action visible in the safe area.
- Reuse the same presentation in app and share extension. Preserve cancellation, current pipeline choice, direct-import order, and temporary-copy ownership.

**Exit:** PDF and image imports, manual pipeline change, cancellation, and processing errors are understandable and recoverable in simulator app and extension flows.

### U4 — Filename selection and result

- Rework date choice, ranked words, manual correction, and actual filename preview as one focused decision screen. Give suggestions readable emphasis and clear ordered selection.
- Rework the result into a concise export decision, including configured-folder save, Share, Save to Files, filename edit, canceled export, and completion.

**Exit:** interactive naming/export and unattended success/failure are verified in simulator; no save occurs before required confirmation. Cover multi-selection, ambiguous date, missing words, collision/error, and export cancellation.

### U5 — Polish and final validation

- Audit every screen in app and extension for light/dark, increased contrast, large Dynamic Type, VoiceOver order, keyboard, small device width, empty/error/loading/completion states, and one-handed reach.
- Inspect actual icon appearances separately; avoid changing the accepted motif unless the visual review finds a concrete problem.
- Run full `make verify` and optimized `make test-release`; compare against U0 captures. After U4, perform only targeted physical-iPhone checks needed for system sheet, Files provider, or extension behavior that simulator cannot establish.
- Update README/PROJECT/ARCHITECTURE and record any unresolved device evidence. Do not claim a usability improvement from green tests alone; the visual and task-flow review is required.

**Exit:** all major journeys can be completed without hunting for the next action; no regression in pipeline data, source preservation, unattended saving, or export; documented limitations are explicit.

## Verification evidence and limits (2026-10-12)

- On an isolated iPhone 17 simulator running iOS 27, the final `make verify` passed 41 unit tests, all three UI tests (template and word choice, app-to-share-extension, and import/Swipe Delete), static analysis, and optimized device-SDK Release build. The final `make test-release` passed all 41 unit tests.
- Home was visually checked in light and dark appearance; a second screenshot used accessibility-large text and Increased Contrast in dark appearance. The word-selection screen was inspected from a UI-test screenshot. The selected word has a checkmark, and the current primary action remains visible at the bottom. Targeted template/word-choice and OCR/import/delete UI tests also passed at accessibility-large text size.
- At accessibility-large text size, a template composer embedded as a single `Form` row failed to respond reliably to a date-chip tap. Moving it to its own `ScrollView` fixed the interaction; the full chip-to-filename UI test passed afterward.
- The UI tests initially exposed a hidden source filename in the share extension; the review screen now displays it above the preview. A test-only fixture button at the bottom of a long list was moved to the toolbar to avoid interception by the persistent import action. The final fresh-simulator gate passed after both fixes.
- Manual VoiceOver navigation, keyboard traversal, all error states at maximum text size, Home Screen icon tint switching, and actual third-party Files-provider behavior remain unverified. The latter provider and extension resource questions are also recorded in PLAN.md. No new physical-iPhone verification was necessary for the functional UI changes; the simulator app-to-extension path passed.

## Decisions and scope

The recommended direction is a task-focused navigation stack, no tab bar, system-native surfaces, restrained blue accent, and a separate template composer. These are reversible UI choices that preserve the accepted product behavior. Do not use the makeover to add a document library, cloud service, new processing steps, or change the default-pipeline policy. Defer localization and new icon artwork unless a separate product decision requests them.
