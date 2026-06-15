# Analysis Log

This file is an append-only log of analyses (investigations, reviews, audits) performed on this repository. The newest entry is at the top. See [AGENTS.md](AGENTS.md#analysis-documentation) for the recording rules.

---

## Native SDK Preference — App Audit

- **Date:** 2026-06-15
- **AI model:** Claude Opus 4.8 (`claude-opus-4-8`)
- **Prompt:** "Analyze the whole app for the native SDK preference rule."

### Result

Audit of the codebase against the **Native SDK Preference** rule (AGENTS.md): custom implementations where an Apple framework / Swift native solution exists.

#### 🔴 Clear opportunities (native exists, custom code used without a documented reason)

**1. Date parsing — `DocNest/Infrastructure/OCR/DocumentDateExtractor.swift`**
~130 lines of hand-written `NSRegularExpression` patterns + 17 `DateFormatter` permutations for EN/DE dates. Apple's native solution is **`NSDataDetector`** (`.date` checking type), which detects dates in natural-language text across locales and returns a `Date` directly. The custom approach also has latent bugs the native one avoids (e.g. `MM/dd` vs `dd.MM` ambiguity; the `formatter.locale = nil` line at `:73` is a no-op). Strongest candidate — a pure data-detection task the native API directly covers.

**2. Settings & About windows — `DocNest/App/AboutWindowController.swift`**
Three hand-built `NSWindowController` subclasses (`About`, `Help`, `Settings`) wired through `CommandGroup(replacing: .appSettings)` in `DocNestApp.swift:344`. Native equivalents:
- Settings → SwiftUI **`Settings { … }`** scene (auto-wires ⌘, menu item, standard window).
- About → **`NSApplication.orderFrontStandardAboutPanel`** or a `Window` scene.

The Help window is reasonable as custom; Settings/About are the textbook native-scene cases.

**3. Search field — `DocNest/Shared/SearchToolbarField.swift`**
A full `NSSearchField` `NSViewRepresentable` bridge. SwiftUI's native **`.searchable`** modifier covers this. *Caveat:* it's placed in a custom `.principal` toolbar slot with a programmatic focus token, which `.searchable` doesn't map onto cleanly — "native exists but may not fit 100%", so raise before migrating.

#### 🟡 Documented "native didn't fit" cases (rule says *ask* — already justified in comments)

**4. Drag-to-Finder — `DocNest/Features/Documents/DocumentDragSupport.swift:84`**
Custom `NSDraggingSource` bridge. The comment explicitly states *"SwiftUI's standard file drag support did not fit DocNest's mixed internal and external drag contract."* This is exactly the rule's escape hatch, and it's documented. Native alternatives (`.draggable`, `NSItemProvider` file promises) genuinely struggle with deferred temp-file materialization — reasonable to keep.

**5. Resizable column list — `DocNest/Features/Documents/DocumentListView.swift:1177`**
`ResizableColumnHeader` + manual `DragGesture` width math + `NSCursor` management (`ResizeHandleCursorState.swift`). SwiftUI's native **`Table`** (macOS 12+) gives resizable/reorderable columns for free. Likely won't fit 100% (thumbnail view mode, custom label-chip cells, the drag handle) — an *ask-the-user* case, currently undocumented as a deliberate choice.

#### 🟢 Already compliant (good native usage)

- **OCR**: `Vision` (`VNRecognizeTextRequest`) + `PDFKit` + `CoreGraphics` rendering — all native. OCRmyPDF is an *optional* external tool with Vision fallback (intentional design, not a reinvention).
- **Folder monitoring** (`FolderMonitorService.swift`): `FSEvents` is the correct native API for recursive folder watching (not a custom poller).
- **Search matching** (`SearchDocumentsUseCase.swift:111`): native `String.range(of:options:[.caseInsensitive,.diacriticInsensitive])`.
- **Layout**: `NavigationSplitView` + `.inspector` (merged from PR #5) replaced the old hand-rolled `HStack`.
- `StringNormalization`, `DeferredSelectionState` — trivial domain logic with no single native equivalent.

### Recommendation

Act without hesitation on **#1 (DocumentDateExtractor → NSDataDetector)** — a clean, well-tested native replacement for a large, bug-prone custom implementation. **#2 (Settings/About scenes)** is also a safe, idiomatic win. **#3–#5** are genuine "native exists but may not fit 100%" cases that the rule says to raise with the user before changing.
