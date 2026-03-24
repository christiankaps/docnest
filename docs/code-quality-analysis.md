# DocNest — Code Quality Analysis

**Date:** 2026-03-23
**Scope:** Full source review — App, Domain, Infrastructure, Features, Shared layers
**Files reviewed:** 29 Swift source files (~4 500 lines of production code)

---

## Summary

The codebase has a solid layered architecture with clear separation of concerns. There are **no external package dependencies** and the project relies exclusively on Apple frameworks. The most significant issues are a **duplicated name-normalisation function** (copy-pasted across four use cases), a **dead loop** in watch-folder monitoring, **production preview/sample code** in a model entity, and several instances of `static var` computed properties that allocate a new object on every access.

---

## 1. Code Smells

### 1.1 Duplicated `normalizedName` function (4 files)

The exact same whitespace-collapsing logic is copy-pasted into four separate use-case enums, with only the thrown error type differing.

| File | Function name | Error thrown |
|------|--------------|--------------|
| `ManageLabelsUseCase.swift:146` | `normalizedLabelName(from:)` | `LabelValidationError.emptyName` |
| `ManageLabelGroupsUseCase.swift:46` | `normalizedName(from:)` | `LabelGroupValidationError.emptyName` |
| `ManageSmartFoldersUseCase.swift:57` | `normalizedName(from:)` | `SmartFolderValidationError.emptyName` |
| `ManageWatchFoldersUseCase.swift:74` | `normalizedName(from:)` | `WatchFolderValidationError.emptyName` |

All four implementations are identical:
```swift
// same body in all four files
let collapsed = rawName
    .components(separatedBy: .whitespacesAndNewlines)
    .filter { !$0.isEmpty }
    .joined(separator: " ")
guard !collapsed.isEmpty else { throw <SomeError>.emptyName }
return collapsed
```

**Recommendation:** Extract to a shared helper in `Shared/` (e.g. `StringNormalization.collapsedWhitespace(_:)`) and pass the validation error as a parameter.

---

### 1.2 `LibraryCoordinator` is a God Object (786 lines)

`LibraryCoordinator.swift` accumulates too many unrelated responsibilities:

- UI state flags (`isImporting`, `isDropTargeted`, `isQuickLabelPickerPresented`, …)
- Document filtering and recomputation
- Label assignment and drag-and-drop confirmation
- Smart-folder helper resolution
- Watch-folder monitoring lifecycle
- OCR task orchestration
- Import/export coordination
- Binding helpers and display-string generation

This makes the class hard to test in isolation and difficult to reason about as a unit.

**Recommendation:** Incrementally extract into smaller, focused types (e.g. `WatchFolderMonitor`, `OCRCoordinator`) as vertical slices of future work.

---

### 1.3 Error messages routed to `importSummaryMessage` for non-import errors

Errors from `restoreDocumentFromBin`, `moveToBin`, `deleteSelectedDocumentsFromKeyboard`, and label-assignment operations are all silently routed to `coordinator.importSummaryMessage`:

```swift
// LibraryCoordinator.swift:299, 308, 323, 332, 354, 393, 421, ...
} catch {
    importSummaryMessage = error.localizedDescription  // misleading property name
}
```

The property name implies it only carries import status, making it harder to understand what state the toast will show.

**Recommendation:** Rename to `pendingUserMessage` or introduce a dedicated error-display mechanism.

---

### 1.4 `ManageLabelsUseCase.update` calls `modelContext.save()` four times

```swift
// ManageLabelsUseCase.swift:91–96
static func update(_ label: LabelTag, name: String, color: LabelColor, icon: String?, groupID: UUID?, using modelContext: ModelContext) throws {
    let renamedLabel = try rename(label, to: name, using: modelContext)       // save #1 (possibly #2)
    try changeColor(of: renamedLabel, to: color, using: modelContext)         // save #2
    try changeIcon(of: renamedLabel, to: icon, using: modelContext)           // save #3
    try assignToGroup(renamedLabel, groupID: groupID, using: modelContext)    // save #4
}
```

Each individual method saves unconditionally. A single atomic save at the end of `update` would suffice and reduce I/O.

---

### 1.5 `SearchDocumentsUseCase.matchesAllSearchTerms` — verbose manual loop

The method uses an explicit `for`/`continue` pattern where `allSatisfy` with `any` would be clearer and avoid the reader having to trace control flow manually:

```swift
// SearchDocumentsUseCase.swift:32–64
for term in searchTerms {
    let titleMatches = ...
    if titleMatches { continue }
    let fileNameMatches = ...
    if fileNameMatches { continue }
    ...
    return false
}
return true
```

**Recommendation:** Replace the body with `searchTerms.allSatisfy { term in ... }`.

---

### 1.6 Regex patterns compiled on every call

`ImportPDFDocumentsUseCase.parseFilenameFromContentDisposition` compiles three `NSRegularExpression` instances inside a loop on every invocation:

```swift
// ImportPDFDocumentsUseCase.swift:290–304
let patterns: [String] = ["filename\\*=...", "filename=\"...\"", "filename=..."]
for pattern in patterns {
    if let regex = try? NSRegularExpression(pattern: pattern), ... {
```

Regex compilation is expensive. These static patterns should be compiled once as `static let` properties.

---

### 1.7 `static var` computed properties create new instances on every access

Two private extensions allocate a new `JSONEncoder` / `JSONDecoder` on every call:

```swift
// DocumentLibraryService.swift:292–306
private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {   // `var` — new instance each access
        let encoder = JSONEncoder()
        ...
        return encoder
    }
}
private extension JSONDecoder {
    static var libraryManifest: JSONDecoder { // same issue
        ...
    }
}
```

**Recommendation:** Change `var` to `let` to create a single shared instance.

---

### 1.8 Variable shadowing of `self.activeDocuments`

Inside `assignDroppedLabelToDocuments`, a local variable reuses the same name as the instance property:

```swift
// LibraryCoordinator.swift:361
let activeDocuments = documents.filter { $0.trashedAt == nil }
// shadows self.activeDocuments
```

This is error-prone — a future reader (or refactor) might unintentionally read the wrong one.

---

### 1.9 `confirmDroppedLabelAssignment(allDocuments:)` redundant parameter

`RootViewDialogsModifier` passes `allDocuments` (from `@Query`) down into the coordinator, even though the coordinator already caches the same documents in `activeDocuments` and `trashedDocuments`:

```swift
// RootView.swift:309
coordinator.confirmDroppedLabelAssignment(allDocuments: allDocuments)
```

The coordinator could instead look up documents from its own state, removing this unnecessary coupling between the view and the coordinator's internal data.

---

### 1.10 `AppRootView` and `LibrarySessionController` defined in `DocNestApp.swift`

The 613-line entry-point file hosts six distinct concerns: the `@main` struct, `AppDelegate`, menu command groups, `AppearanceMode`, `AppRootView` (the full main content view including drop handling and alert logic), and `LibrarySessionController` (a 175-line class with library lifecycle, lock management, statistics, and URL queuing).

`LibrarySessionController` in particular is large enough to warrant its own file.

---

## 2. Dead Code

### 2.1 Unreachable loop in `refreshWatchFolderMonitors` ← **Bug**

```swift
// LibraryCoordinator.swift:651–655
let currentIDs = Set(allWatchFolders.map(\.id))
for folder in allWatchFolders where !currentIDs.contains(folder.id) {
    // This body can NEVER execute.
    // currentIDs is built from allWatchFolders, so every folder.id is in currentIDs.
    folderMonitorService.stopMonitoring(id: folder.id)
}
```

The intent was presumably to stop monitors for folders that have been deleted — but the deleted folders are no longer in `allWatchFolders`, so the loop over that same array will never find a missing ID. The stop-for-deleted logic is effectively absent.

**Recommendation:** The loop should iterate over `folderMonitorService`'s currently-monitored IDs and stop any that are not in `currentIDs`.

---

### 2.2 `DocumentRecord.makeSamples` is production code

```swift
// DocumentRecord.swift:54
static func makeSamples(labels: (finance: LabelTag, tax: LabelTag, contracts: LabelTag)) -> [DocumentRecord] { ... }
```

This is a preview/test factory that ships in production binaries. It has no callers other than SwiftUI previews.

**Recommendation:** Wrap in `#if DEBUG` or move to a `PreviewHelpers.swift` file in a debug-only target group.

---

### 2.3 `Diagnostics` directory created but never used

`DocumentLibraryService.requiredDirectories` includes `"Diagnostics"`, which is created on library initialisation and validated on open — but nothing in the codebase writes to or reads from it:

```swift
// DocumentLibraryService.swift:39–44
private static let requiredDirectories = [
    "Metadata",
    "Originals",
    "Previews",
    "Diagnostics"   // no code uses this directory
]
```

**Recommendation:** Either remove it from the required-directories list (and stop creating it), or implement the intended diagnostics feature.

---

### 2.4 `AppearanceMode` defined alongside app entry point

`AppearanceMode` (the system/light/dark enum) is defined at the top level of `DocNestApp.swift` but is only used by `AppRootView` in the same file. It's not referenced anywhere else. As a standalone type it adds noise to the entry-point file.

---

## 3. Unnecessary Dependencies and Coupling

### 3.1 `ExtractDocumentTextUseCase` silently swallows save errors

```swift
// ExtractDocumentTextUseCase.swift:45
try? modelContext.save()
```

If the save fails (e.g. due to a schema error or disk full), the OCR results are lost silently. Given that OCR is CPU-intensive, losing results without any signal is costly.

**Recommendation:** At minimum log the error; ideally propagate it or surface it through the coordinator.

---

### 3.2 Tight coupling: `LibraryCoordinator` instantiates `FolderMonitorService` directly

```swift
// LibraryCoordinator.swift:80
private let folderMonitorService = FolderMonitorService()
```

`FolderMonitorService` is constructed internally, making it impossible to inject a mock or stub for unit testing. The coordinator cannot be tested in isolation without real filesystem monitoring.

**Recommendation:** Accept `FolderMonitorService` via the initialiser (or via a protocol) to enable dependency injection.

---

### 3.3 `LibraryCoordinator.modelContext` and `libraryURL` are injected via mutation

```swift
// LibraryCoordinator.swift:39–40
var libraryURL: URL?
var modelContext: ModelContext?
```

Both properties start as `nil` and are set post-construction by `RootView.task`. This means any method that uses them must guard against `nil`, and it's possible to call coordinator methods before these are set. A constructor-injection approach would eliminate the optionality.

---

### 3.4 Notification-based command dispatch adds indirection

Menu commands post `NotificationCenter` notifications that `RootView` receives and maps to coordinator calls:

```swift
// DocNestApp.swift:188–194
Button("Find") {
    NotificationCenter.default.post(name: .docNestFocusSearch, object: nil)
}
```

```swift
// RootView.swift:427–438
.onReceive(NotificationCenter.default.publisher(for: .docNestFocusSearch)) { _ in
    coordinator.searchFocusRequestToken += 1
}
```

The `FocusedValue` mechanism (already used for `exportDocumentsAction` and `pasteDocumentsAction`) is a more idiomatic SwiftUI approach for menu-to-view communication and avoids the global notification channel. Three commands (`docNestFocusSearch`, `docNestQuickLabelPicker`, `docNestLabelManager`, `docNestWatchFolderSettings`) could be refactored this way.

---

### 3.5 `JSONEncoder.prettyPrinted` / `JSONDecoder.libraryManifest` used across multiple call-sites

Both extensions are `private` to `DocumentLibraryService.swift`, which is correct scope, but because they are `static var` computed properties (see §1.7) they allocate a fresh object on every use — including in tight paths like `writeLockFile`, which is called every 30 seconds from a timer.

---

### 3.6 `ImportPDFDocumentsUseCase` blocks a thread with `process.waitUntilExit()`

```swift
// ImportPDFDocumentsUseCase.swift:463
try process.run()
process.waitUntilExit()
```

`extractZipFile` is called from within a `Task.detached` block during import, but `waitUntilExit()` blocks the cooperative thread-pool thread for the duration of the `ditto` subprocess. For large ZIP archives this can stall other async work running on the same thread.

**Recommendation:** Use `Process.terminationHandler` with a continuation or `AsyncStream` to avoid blocking.

---

## 4. Minor Observations

| # | Location | Observation |
|---|----------|-------------|
| 4.1 | `LibraryCoordinator.swift:82` | `labelFilterApplyDelay: .milliseconds(75)` is a magic number with no explanation in the surrounding code. A brief comment on why 75 ms was chosen would aid future tuning. |
| 4.2 | `LibraryCoordinator.swift:754` | `parseDroppedDocumentIDs` is `internal` (no access modifier) but is only used within the coordinator. Should be `private`. |
| 4.3 | `ExportDocumentsUseCase.swift:134–137` | The inline comment "off the main actor is not possible since we need collision resolution to be sequential" documents a known limitation but was noted as an area of incomplete refactoring in `todo.md`. |
| 4.4 | `ImportPDFDocumentsUseCase.swift:349` | `let fileURL = url` is a redundant assignment (the variable is immediately used as-is). |
| 4.5 | `RootViewChangeHandlers` | Five fingerprint computed properties are re-evaluated on every `body` call triggered by any state change in the view hierarchy, not just actual data mutations. SwiftUI's `onChange(of:)` only fires when the value changes, so correctness is maintained, but the hashing cost runs on every render. |
| 4.6 | `DocNestApp.swift:54` | Menu-item titles `["Writing Tools", "AutoFill"]` are hardcoded strings. If Apple renames these in a future macOS release the filtering will silently break. |

---

## 5. Dependency Inventory

No external Swift Package Manager, CocoaPods, or Carthage dependencies are used. All imports are Apple system frameworks.

| Framework | Used in | Justified? |
|-----------|---------|-----------|
| `SwiftUI` | App, Features, Shared | Yes — primary UI framework |
| `SwiftData` | Domain, Infrastructure, App | Yes — persistence layer |
| `AppKit` | App, Infrastructure, Export | Yes — macOS-specific panels, windows, pasteboard |
| `Foundation` | All layers | Yes — core utilities |
| `PDFKit` | Import, OCR, Preview | Yes — PDF reading and rendering |
| `CryptoKit` | `ImportPDFDocumentsUseCase` | Yes — SHA-256 content hashing |
| `Vision` | `OCRTextExtractionService` | Yes — text recognition |
| `OSLog` | Coordinator, Use Cases | Yes — structured logging |
| `UniformTypeIdentifiers` | Import, Export, Root | Yes — UTType conformance checks |

No unnecessary framework imports were found at the file level.

---

## 6. Priority Summary

| Priority | Finding | File(s) |
|----------|---------|---------|
| **High** | Dead loop in `refreshWatchFolderMonitors` (monitors for deleted folders are never stopped) | `LibraryCoordinator.swift:651` |
| **High** | Duplicated `normalizedName` across 4 use cases | `Manage*UseCase.swift` |
| **High** | `static var` computed properties allocating new encoder/decoder each call | `DocumentLibraryService.swift:292–306` |
| **Medium** | `makeSamples` factory ships in production binary | `DocumentRecord.swift:54` |
| **Medium** | `Diagnostics` directory created but unused | `DocumentLibraryService.swift:39` |
| **Medium** | Silent `try?` swallows OCR save errors | `ExtractDocumentTextUseCase.swift:45` |
| **Medium** | `ManageLabelsUseCase.update` triggers 4 saves for one operation | `ManageLabelsUseCase.swift:91` |
| **Medium** | Regex patterns compiled on every call to `parseFilenameFromContentDisposition` | `ImportPDFDocumentsUseCase.swift:296` |
| **Low** | `parseDroppedDocumentIDs` missing `private` modifier | `LibraryCoordinator.swift:754` |
| **Low** | Notification-based command dispatch; `FocusedValue` already available | `DocNestApp.swift`, `RootView.swift` |
| **Low** | Hardcoded macOS menu item titles | `DocNestApp.swift:54,66` |
| **Low** | `process.waitUntilExit()` blocks cooperative thread during ZIP extraction | `ImportPDFDocumentsUseCase.swift:463` |
| **Low** | `LibraryCoordinator` God Object (786 lines, 10+ responsibilities) | `LibraryCoordinator.swift` |
