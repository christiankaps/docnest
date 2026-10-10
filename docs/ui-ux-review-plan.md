# UI/UX Review and Makeover Plan

Status: makeover delivery under revised scope, 2026-10-10. The user requested completion without solving the narrow-window crash. UX-15 and minimum-size populated-window acceptance are explicitly deferred. See the [findings and validation report](ui-ux-review.md) for implemented changes and actual verification; the original comprehensive review checklist below is not a claim that every matrix combination was exercised.

## Outcome

Make DocNest intuitive, modern, and native to macOS 27, with consistent alignment and polished behavior across every supported state, including when no library is open. Review the complete experience, fix confirmed findings, and consider a complete visual and interaction makeover when incremental fixes cannot produce a coherent result.

Preserve the current library format, local data ownership, shared import pipeline, and documented functionality. A makeover may change presentation and interaction structure; removing product capabilities or changing storage behavior requires a separate decision.

## 1. Establish a trustworthy baseline

- Build the current checkout using the project commands. Confirm the executable path, revision, macOS version, and Xcode version being reviewed. Resolve the known UI automation collision with the older `/Applications/DocNest.app` before relying on its results; do not overwrite the installed app or use real user libraries for testing.
- Use disposable current-format libraries: empty, representative, and large. Include long names, multiple label groups, unit values, physical locations, missing originals, image-only PDFs, and mixed document dates. Record fixture size and machine configuration for repeatable performance comparisons.
- Capture screenshots and workflow observations for Light and Dark appearance, minimum supported window size, a normal desktop window, fullscreen, inspector hidden/visible, and resized sidebar/inspector configurations. Include increased contrast, reduced transparency, and keyboard focus where they change presentation.
- Treat source inspection as a source of hypotheses. Confirm visible defects in the running build; label anything that cannot be reproduced as unverified.

Deliverable: a reproducible screen/state inventory with screenshots and baseline observations.

## 2. Review tasks and all application states

| Surface or state | What to evaluate |
| --- | --- |
| No library open | Clear purpose, immediately discoverable Create/Open actions, sensible initial window size, useful copy, keyboard access, menu availability, and dropped library/PDF behavior. Remove misleading placeholder content if a simpler welcome screen works better. |
| Library opening, failure, and close | Loading feedback, missing or unsupported library recovery, actionable errors, cancellation, and a clean return to the welcome state. |
| Empty library and empty views | First import guidance; distinguish empty library, no search results, empty Bin, and no selection; provide a useful contextual next action. |
| Main window and toolbar | Action hierarchy, search discoverability, control grouping, overflow at narrow widths, title-bar integration, sidebar/inspector toggles, and consistency across window states. |
| Sidebar | Scanability of sections, labels, groups, smart folders, and locations; counts, disclosure controls, selection/filter meaning, reorder feedback, and context menus. |
| List and thumbnails | Column alignment, readable density, sorting/grouping, long text, selection states, keyboard order, drag targets, inline values, loading, and empty results. |
| Inspector and preview | Single/multiple/no selection, field hierarchy, edit affordances, label/value controls, availability/location controls, missing files, preview sizing, and action placement. |
| Editors and settings | Consistent form labels, field widths, button order, validation, save/cancel behavior, label/group/smart-folder/location editors, watch folders, and appearance settings. |
| Background work and errors | Import/OCR/watch-folder progress, cancellation, summaries, recovery, alert severity, and comprehensible feedback without disrupting ongoing work. |
| Export, sharing, and deletion | Discoverability, native dialogs, Finder access, unambiguous destructive actions, confirmation, and truthful completion feedback. |

Walk through creating/opening a library, importing a PDF, finding it, labeling it, previewing it, editing its metadata, exporting/sharing it, moving it to Bin, restoring it, and closing/reopening the library. Repeat key tasks using the keyboard alone. Record confusing terms, dead ends, redundant steps, ambiguous icons, and unexpected state changes. Do not infer user usability success from screenshots alone; validate representative tasks with user walkthroughs when possible.

## 3. Audit visual consistency and macOS behavior

- Check shared leading/trailing edges, text baselines, icon/text alignment, section spacing, row heights, column headers/cells, form labels/fields, sheet margins, button alignment, divider continuity, and toolbar/content boundaries. Distinguish intentional system spacing from accidental offsets.
- Inspect wrapping, truncation, clipping, and overlap with long content, large values, empty fields, all supported window sizes, and appearance/accessibility variations.
- Consolidate recurring spacing, typography, icon sizing, and control treatments into a small shared system, using native control metrics and existing design helpers where appropriate. Avoid unrelated per-view padding fixes that merely move a mismatch elsewhere.
- Review native materials, semantic colors, system typography, SF Symbols, standard controls, focus rings, selection emphasis, active/inactive windows, sheets, popovers, menus, shortcuts, and full-screen behavior against Apple guidance.
- Check VoiceOver names/roles/values, reading order, keyboard reachability, visible focus, contrast, non-color status cues, and motion/transparency preferences. Essential actions must not depend on hover or undiscoverable gestures.
- Measure search, selection, scrolling, resizing, and preview responsiveness with the baseline datasets. Profile confirmed regressions; preserve bounded caching and cancellation. Set numerical budgets from measurements rather than inventing unsupported targets.

References: [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos/), [Windows](https://developer.apple.com/design/human-interface-guidelines/windows), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), and the project's [UI concepts](ui-concepts.md), [requirements](requirements.md), and [testing policy](testing.md).

## 4. Record findings and choose the design direction

Create the findings register only after the baseline review. Each entry needs an ID, severity, affected task/state, reproduction steps, screenshot or other evidence, expected behavior, proposed fix, acceptance check, and status. Separate confirmed defects from recommendations and unknowns.

Prioritize blocked or unsafe tasks first, then confusing workflows and inaccessible controls, then layout/readability inconsistencies and cosmetic polish. Assign every confirmed finding a disposition; a deferred issue needs a reason and an explicit acceptance decision.

Compare two concrete directions using the same representative screens and tasks:

1. Targeted improvements that preserve the current information architecture.
2. A cohesive makeover of the welcome screen, window composition, toolbar, sidebar, browser, inspector, and forms where the findings justify it.

Recommendation to explore first: a focused welcome screen when no library is open, with clear Create/Open actions and no inactive document inspector or organization placeholders. This is a design hypothesis, not an accepted redesign.

Provide reviewable mockups or an interactive prototype for no-library, empty-library, populated-library, selected-document, and narrow-window states. Explain the effect on task discoverability, alignment, accessibility, native behavior, and implementation scope. Choose the smallest direction that resolves the findings coherently. Present consequential navigation or workflow changes to the user with a recommendation and concrete before/after examples before implementation; resolve minor reversible styling details autonomously.

## 5. Fix findings in coherent slices

After the direction is established, implement in this order unless the severity register requires otherwise:

1. Welcome/no-library experience, empty states, and recovery paths.
2. Shared visual rules, main-window composition, toolbar, and sidebar.
3. Document list/thumbnails, selection, search, and inspector.
4. Editors/settings, background feedback, sharing/export, and destructive flows.
5. Cross-screen alignment, accessibility, and responsive-layout polish.

For each slice, inspect the diff, verify affected tasks, and compare the same before/after screenshots. Recheck neighboring surfaces after changing shared metrics. Add meaningful regression coverage for behavior and layout invariants; use visual inspection for cosmetic details rather than tests that duplicate padding constants. Update `docs/ui-concepts.md` and affected requirements when behavior or accepted design rules change.

## 6. Acceptance and completion

- No unresolved confirmed alignment inconsistency, clipping, overlap, or unreadable control across the agreed screen/state matrix. Intentional differences are explained in the accepted design rules.
- No-library, empty-library, no-results, no-selection, loading, and error states each explain the situation and offer an appropriate next action. Library-dependent commands have sensible availability.
- Core tasks work through discoverable controls, native menus, and applicable keyboard shortcuts. Search focus, selection, drag/drop, preview, and close/reopen behavior remain reliable.
- Light/Dark appearance and the reviewed accessibility settings are usable; all essential actions are keyboard-accessible and have meaningful accessibility descriptions.
- `make test` and `make analyze` pass. Run `make test-ui` against the verified current executable; resolve test wiring issues before interpreting failures. Complete manual visual checks that automation cannot establish, including alignment and native appearance.
- Performance meets the measured, agreed budgets. No material regression in startup, selection, search, scrolling, or preview responsiveness.
- Review the entire change against the findings register. Reopen failed fixes; report verification gaps explicitly. A skipped or misdirected UI run does not establish completion.
- Commit verified coherent changes according to project policy. Publishing or releasing remains a separate action.

Deliverables: baseline evidence, findings register, selected design/prototype, fixes with before/after evidence, updated UI documentation, and a final validation report. Retire this plan after findings are resolved and durable decisions are consolidated.
