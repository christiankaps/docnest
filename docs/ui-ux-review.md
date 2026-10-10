# UI/UX Review — macOS 27

Status: makeover delivered under revised scope, 2026-10-10. The user explicitly deferred the narrow-window crash (UX-15); it is excluded from this delivery. This report distinguishes confirmed findings, implemented changes, and remaining verification. It is the findings register for [the review plan](ui-ux-review-plan.md).

## Environment and evidence

- Baseline source: `63b1d3c`; macOS 27.0.1, Xcode 27.0, Apple silicon.
- Review app: `com.kaps.docnest.review`, built into `/tmp/docnest-ux-prototype-derived`. Test app: `com.kaps.docnest.uitesting`, built into `/tmp/docnest-ui-derived`. Both use disposable libraries and separate preferences from the installed app.
- Baseline screenshots: [welcome](review-evidence/ui-ux/before-welcome.png), [empty library](review-evidence/ui-ux/before-empty-library.png).
- Welcome prototype: [Light appearance](review-evidence/ui-ux/after-welcome-light.png).
- Review snapshots: [selected document](review-evidence/ui-ux/review-selected-document.png), [thumbnails](review-evidence/ui-ux/review-thumbnails.png), [label popover](review-evidence/ui-ux/review-label-popover.png), and [original label Settings](review-evidence/ui-ux/before-label-settings.png). These are intermediate review builds, not evidence of a successful final UI rerun.
- UI test screenshots are retained in result bundles. Automated pass/fail results alone do not establish visual polish.

## Design direction

Choose a focused makeover while retaining the sidebar, document browser, and inspector. The current structure fits the core task sequence; replacing it would add scope without evidence of a better workflow. The no-library state needs a single welcome surface because inactive organization and document panels compete with its only useful actions.

Compared with isolated padding fixes, the selected approach establishes shared content edges, removes duplicate window commands, makes empty states task-specific, fixes native text editing, and reduces the inspector’s preview minimum to leave more room for metadata. No product capabilities or storage behavior are removed.

## Findings

| ID | Severity | Evidence and reproduction | Fix and acceptance check | Status |
| --- | --- | --- | --- | --- |
| UX-01 | Medium | Launch without a library: repeated no-library/no-label/no-selection messages fill three columns; see baseline welcome screenshot. | One centered welcome surface with Create/Open actions, meaningful copy, and smaller supported dimensions. | Implemented; normal-size Light/Dark and welcome UI checks passed before final rerun limitation |
| UX-02 | Medium | Baseline menu bar exposes two View menus. | Put inspector visibility in the existing native View menu; exactly one View menu. | Implemented and confirmed in running prototype |
| UX-03 | Medium | Search or select empty Bin: the baseline always offers “No Documents” and Import. | Distinguish initial import, search, filter, and Bin states; Clear Search and Show All Documents recover context. | New UI workflow passes |
| UX-04 | Medium | `DocumentListView` header uses 14-point horizontal padding while rows use 12; populated screenshot also confirms headers omit the trailing 16-point drag column, shifting optional columns by 26 points. | Share one inset and reserve the trailing drag column in both headers and rows. | Implemented; normal-size populated screenshots reviewed; compact check excluded |
| UX-05 | Medium | Inspector preview minimum 420 plus metadata minimum 240 and their padding consume more than the available content height in a 700-point window. | Reduce split-pane minimums and use consistent 16-point insets; verify preview and metadata at minimum window height. | Implemented; normal-size preview reviewed; minimum-size acceptance deferred with UX-15 |
| UX-06 | Medium | Baseline sidebar screenshot: Library heading starts at the content edge; other headings start after decorative icons. Add controls expose generic “Add” labels; inspector date/label removal controls expose “Refresh” or “Close”. | Align section headings and give each Add control a specific accessibility label. | Implemented; sidebar alignment reviewed; accessibility names inspected |
| UX-07 | High | Location rename UI test: Command-A leaves “Archive Box” selected as documents rather than text; typing produces “Shelf AArchive Box”. | Route editing commands to the active text responder, then use document actions where appropriate. Restore native Cut/Copy actions. Verify rename and search text editing. | Fixed; location rename regression passes |
| UX-08 | Medium | UI automation launches a different app when identities share build paths; a root identifier is also lost on the native split view. Root identifiers overwrite welcome-button identifiers. | Dedicated test identity/path, bundle-aware test cleanup, and stable control identifiers. | Library restoration and search-focus UI tests pass |
| UX-09 | Low | No-library drop handler accepts PDFs only to report an error and does not open dropped library packages. | Open a dropped `.docnestlibrary`; retain actionable guidance for PDFs without an open library. | Implemented; source checked; end-to-end drop verification remains unperformed |
| UX-10 | High | Clicking Assign Labels with a selected document crashes in SwiftUI environment lookup (crash report 2026-10-09 23:19). | Inject the library coordinator into the toolbar popover; use its native surface and verify its filter field is reachable. | Fixed; focused UI regression passes |
| UX-11 | Medium | Populated screenshot: selecting a document changes the window title to “Preview”; multi-selection uses “Selection”. | Keep the library name as the window title, independent of inspector selection. | Implemented; Review Library title confirmed in screenshots |
| UX-12 | High | Command-Comma logs “Please use SettingsLink” and fails to open Settings during the visual audit. | Replace AppKit selector dispatch with SettingsLink/openSettings; verify the native Settings window appears. | Fixed; native window confirmed manually |
| UX-13 | Medium | Label Settings has no New Label/New Group controls and repeats its no-selection instructions; see before-label-settings.png. | Restore the embedded footer, label its actions, and use one empty-state message. | Implemented; build verified; final creation workflow blocked by UI activation limitation |
| UX-14 | Medium | Dark screenshot shows black document drag handles; thumbnail labels/values compress into “F…” and “12…”. | Apply a semantic symbol palette and stack thumbnail chips when they cannot fit horizontally; align cards to the top. | Implemented; stacked values and semantic handles reviewed in Light; final Dark rerun blocked |
| UX-15 | High | Launch a populated library at 960 × 700 content size: AppKit aborts after repeated split-view constraint passes (23:33 and 23:35 crash reports). | Investigate separately. Experimental inspector restructuring was removed; retain the opt-in compact reproducer. | Deferred by user, 2026-10-10 |

No unresolved item is silently treated as accepted. Remaining checks and new findings will be recorded here before completion.

## Reproducing representative fixtures

`Tools/create_review_fixtures.swift` builds disposable empty, representative, or large libraries using the current model. It refuses to overwrite an existing path and accepts 0–2000 documents. Twelve documents include labels/groups, unit values, dates, a physical location, long titles, and one intentionally missing original. Text-bearing PDFs prevent unrelated OCR model availability from blocking layout review.

After building the Debug review app:

```sh
make build DERIVED_DATA_DIR=/tmp/docnest-ux-prototype-derived XCODEBUILD='xcodebuild DOCNEST_APP_BUNDLE_IDENTIFIER=com.kaps.docnest.review'
xcrun swiftc -parse-as-library -target arm64-apple-macos27.0 \
  -module-cache-path /tmp/docnest-ux-swift-cache \
  -I /tmp/docnest-ux-prototype-derived/Build/Products/Debug \
  /tmp/docnest-ux-prototype-derived/Build/Products/Debug/DocNest.app/Contents/MacOS/DocNest.debug.dylib \
  -Xlinker -rpath -Xlinker /tmp/docnest-ux-prototype-derived/Build/Products/Debug/DocNest.app/Contents/MacOS \
  Tools/create_review_fixtures.swift -o /tmp/create-review-fixtures
/tmp/create-review-fixtures /tmp/Representative.docnestlibrary 12
/tmp/create-review-fixtures /tmp/Large.docnestlibrary 1000
```

## Validation and accepted limitations

- `make test DERIVED_DATA_DIR=/tmp/docnest-ux-unit-derived`: passed on 2026-10-10, 200 tests, 2 opt-in tests skipped, 0 failures. Skips: image-only Vision integration (requires installed recognition models) and 10,000-document import stress.
- `make analyze DERIVED_DATA_DIR=/tmp/docnest-ux-unit-derived`: passed on the final source with compiler warnings treated as errors.
- Earlier isolated UI runs verified restoration, search focus, contextual empty states, welcome actions, location create/rename/delete confirmation, and label-popover opening. The representative fixture walkthrough exercised selection, PDF preview, thumbnails, search, and inspector visibility. Screenshots exposed and informed the alignment, title, thumbnail, and Settings fixes.
- Final `make test-ui` attempt on 2026-10-10 was stopped after macOS failed to activate the running test app (`current state: Running Background`). This was an environment activation failure, not a passing UI run. The user explicitly requested completion with this limitation documented. Final Settings creation, compact welcome, and post-change Dark appearance checks therefore remain unverified.
- UX-15 remains reproducible and unresolved. The user explicitly excluded its repair from this makeover; no experimental inspector restructuring is retained. Minimum-size populated-window acceptance is not claimed.
- This delivery does not certify the original exhaustive matrix: the 1,000-document fixture was generated but not fully exercised; fullscreen, increased contrast/reduced transparency, live VoiceOver use, complete keyboard-only journeys, library drag/drop, and every import/export/share/watch-folder path were not manually revalidated. No performance budget or usability-study result is claimed.

The delivered scope is the focused visual and interaction makeover above. The known crash and these verification limits remain visible rather than being treated as successful checks.

### Repeatable UI review

```sh
TEST_RUNNER_DOCNEST_REVIEW_FIXTURE=/tmp/Representative.docnestlibrary \
  make test-ui UI_TESTS=DocNestUITests/DocNestUITests/testReviewFixtureLayouts
```

The test copies the fixture into a disposable directory and reviews the normal-size workflow. Debug-only `DOCNEST_UI_WINDOW_WIDTH` and `DOCNEST_UI_WINDOW_HEIGHT` launch environment values support controlled window sizes. To reproduce the **deferred failure**, add `TEST_RUNNER_DOCNEST_REVIEW_COMPACT_ONLY=1`; this deliberately exercises the known 960 × 700 populated-window crash and is excluded from the standard review run.
