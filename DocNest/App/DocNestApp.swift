import AppKit
import OSLog
import SwiftUI
import SwiftData

// The application entry point for DocNest lives in this file.
//
// It owns process-wide concerns such as scene setup, menu configuration,
// focused-value command wiring, library-session restoration, and app-level
// routing of Services and open-URL events into the currently active library session.
// MARK: - Focused Value for Library Session

private struct LibrarySessionKey: FocusedValueKey {
    typealias Value = LibrarySessionController
}

private struct ExportDocumentsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct PasteDocumentsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct SelectAllDocumentsActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct ToggleInspectorActionKey: FocusedValueKey {
    typealias Value = () -> Void
}

private struct InspectorCollapsedStateKey: FocusedValueKey {
    typealias Value = Bool
}

extension FocusedValues {
    var librarySession: LibrarySessionController? {
        get { self[LibrarySessionKey.self] }
        set { self[LibrarySessionKey.self] = newValue }
    }

    var exportDocumentsAction: (() -> Void)? {
        get { self[ExportDocumentsActionKey.self] }
        set { self[ExportDocumentsActionKey.self] = newValue }
    }

    var pasteDocumentsAction: (() -> Void)? {
        get { self[PasteDocumentsActionKey.self] }
        set { self[PasteDocumentsActionKey.self] = newValue }
    }

    var selectAllDocumentsAction: (() -> Void)? {
        get { self[SelectAllDocumentsActionKey.self] }
        set { self[SelectAllDocumentsActionKey.self] = newValue }
    }

    var toggleInspectorAction: (() -> Void)? {
        get { self[ToggleInspectorActionKey.self] }
        set { self[ToggleInspectorActionKey.self] = newValue }
    }

    var isInspectorCollapsed: Bool? {
        get { self[InspectorCollapsedStateKey.self] }
        set { self[InspectorCollapsedStateKey.self] = newValue }
    }
}

// MARK: - App Delegate

private final class AppDelegate: NSObject, NSApplicationDelegate {
    private var menuCleanupTimer: Timer?
    private var menuCleanupDeadline: Date?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        startMenuCleanupPass()
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        startMenuCleanupPass()
    }

    func applicationWillResignActive(_ notification: Notification) {
        stopMenuCleanupTimer()
    }

    private func configureMainMenu() {
        removeUnwantedMenuItems()
        normalizeMenusRecursively()
        removeEmptyMenus()
    }

    private func startMenuCleanupPass() {
        configureMainMenu()

        menuCleanupDeadline = Date().addingTimeInterval(5)
        if menuCleanupTimer == nil {
            menuCleanupTimer = Timer.scheduledTimer(
                withTimeInterval: 0.5,
                repeats: true
            ) { [weak self] _ in
                guard let self else { return }
                self.configureMainMenu()

                if let deadline = self.menuCleanupDeadline, Date() >= deadline {
                    self.stopMenuCleanupTimer()
                }
            }
        }
    }

    private func stopMenuCleanupTimer() {
        menuCleanupTimer?.invalidate()
        menuCleanupTimer = nil
        menuCleanupDeadline = nil
    }

    /// Removes system-injected menu items that are not relevant for this app.
    private func removeUnwantedMenuItems() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        let unwantedExactTitles: Set<String> = [
            "Writing Tools",
            "Schreibwerkzeuge",
            "AutoFill",
            "Spelling and Grammar",
            "Rechtschreibung und Grammatik",
            "Substitutions",
            "Ersetzungen",
            "Transformations",
            "Umwandlungen",
            "Speech",
            "Sprachausgabe",
            "Start Dictation…",
            "Diktat starten…",
            "Emoji & Symbols",
            "Emoji und Symbole",
            "Toolbar",
            "Show Toolbar",
            "Hide Toolbar",
            "Customize Toolbar…",
            "Show Sidebar",
            "Hide Sidebar"
        ]
        let unwantedTitleFragments = [
            "Writing Tools",
            "Schreibwerkzeuge"
        ]
        removeMenuItems(
            in: mainMenu,
            matchingExactTitles: unwantedExactTitles,
            containingTitleFragments: unwantedTitleFragments
        )

        if let formatMenuItem = mainMenu.items.first(where: { $0.title == "Format" }) {
            mainMenu.removeItem(formatMenuItem)
        }
    }

    private func removeMenuItems(
        in menu: NSMenu,
        matchingExactTitles exactTitles: Set<String>,
        containingTitleFragments titleFragments: [String]
    ) {
        for item in menu.items.reversed() {
            if let submenu = item.submenu {
                removeMenuItems(
                    in: submenu,
                    matchingExactTitles: exactTitles,
                    containingTitleFragments: titleFragments
                )
            }

            let matchesExactTitle = exactTitles.contains(item.title)
            let matchesTitleFragment = titleFragments.contains { fragment in
                item.title.localizedCaseInsensitiveContains(fragment)
            }

            if matchesExactTitle || matchesTitleFragment {
                menu.removeItem(item)
            }
        }
    }

    /// Removes empty items and repeated/edge separators so partially replaced
    /// SwiftUI command groups do not leave visual debris in the menu bar.
    private func normalizeMenusRecursively() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        normalize(menu: mainMenu)
    }

    private func normalize(menu: NSMenu) {
        for item in menu.items {
            if let submenu = item.submenu {
                normalize(menu: submenu)
            }
        }

        var previousWasSeparator = true
        for item in menu.items.reversed() {
            let submenuIsEmpty = item.submenu.map { submenu in
                submenu.items.allSatisfy(\.isSeparatorItem)
            } ?? false

            let isEmptyLeafItem = !item.isSeparatorItem
                && item.submenu == nil
                && item.action == nil
                && item.keyEquivalent.isEmpty
                && item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty

            if submenuIsEmpty || isEmptyLeafItem {
                menu.removeItem(item)
                continue
            }

            if item.isSeparatorItem {
                if previousWasSeparator {
                    menu.removeItem(item)
                }
                previousWasSeparator = true
            } else {
                previousWasSeparator = false
            }
        }
    }

    /// Removes top-level menus that have no meaningful content.
    private func removeEmptyMenus() {
        guard let mainMenu = NSApplication.shared.mainMenu else { return }
        let removableMenus: Set<String> = ["File", "Edit", "Format", "View", "Window", "Help"]
        mainMenu.items.removeAll { item in
            guard removableMenus.contains(item.title) else { return false }
            let realItems = item.submenu?.items.filter { !$0.isSeparatorItem } ?? []
            return realItems.isEmpty
        }
    }
}

@main
struct DocNestApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    @FocusedValue(\.librarySession) private var librarySession
    @FocusedValue(\.exportDocumentsAction) private var exportDocumentsAction
    @FocusedValue(\.pasteDocumentsAction) private var pasteDocumentsAction
    @FocusedValue(\.selectAllDocumentsAction) private var selectAllDocumentsAction
    @FocusedValue(\.toggleInspectorAction) private var toggleInspectorAction
    @FocusedValue(\.isInspectorCollapsed) private var isInspectorCollapsed

    /// Kept alive for the lifetime of the app so macOS can invoke the service.
    private let servicesProvider = ServicesProvider()

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false

        // Suppress system-injected Edit menu items that are not relevant for this app.
        UserDefaults.standard.set(true, forKey: "NSDisabledDictationMenuItem")
        UserDefaults.standard.set(true, forKey: "NSDisabledCharacterPaletteMenuItem")

        // Defer services registration until NSApp is fully initialized.
        DispatchQueue.main.async { [servicesProvider] in
            NSApp.servicesProvider = servicesProvider
        }
    }

    var body: some Scene {
        WindowGroup {
            AppRootView()
                .frame(
                    minWidth: AppSplitViewLayout.minimumWindowWidth,
                    minHeight: AppSplitViewLayout.minimumWindowHeight
                )
        }
        .defaultSize(
            width: AppSplitViewLayout.defaultWindowWidth,
            height: AppSplitViewLayout.defaultWindowHeight
        )
        .windowResizability(.contentMinSize)
        .commands {
            SuppressUnusedMenuCommands()
            DocNestMenuCommands(
                librarySession: librarySession,
                exportDocumentsAction: exportDocumentsAction,
                pasteDocumentsAction: pasteDocumentsAction,
                selectAllDocumentsAction: selectAllDocumentsAction,
                toggleInspectorAction: toggleInspectorAction,
                isInspectorCollapsed: isInspectorCollapsed
            )
        }
    }
}

// MARK: - Menu Commands

/// Suppresses unused system-injected command groups so the menu bar only shows
/// actions DocNest actually supports.
struct SuppressUnusedMenuCommands: Commands {
    var body: some Commands {
        CommandGroup(replacing: .undoRedo) { }
        CommandGroup(replacing: .saveItem) { }
        CommandGroup(replacing: .printItem) { }
        CommandGroup(replacing: .newItem) { }
        CommandGroup(replacing: .systemServices) { }
        CommandGroup(replacing: .windowArrangement) { }
        CommandGroup(replacing: .windowSize) { }
        CommandGroup(replacing: .sidebar) { }
        CommandGroup(replacing: .toolbar) { }
        CommandGroup(replacing: .textFormatting) { }
    }
}

/// App-specific menu bar commands.
struct DocNestMenuCommands: Commands {
    let librarySession: LibrarySessionController?
    let exportDocumentsAction: (() -> Void)?
    let pasteDocumentsAction: (() -> Void)?
    let selectAllDocumentsAction: (() -> Void)?
    let toggleInspectorAction: (() -> Void)?
    let isInspectorCollapsed: Bool?

    var body: some Commands {
        CommandGroup(replacing: .appInfo) {
            Button("About DocNest") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                AboutWindowController.shared.showWindow(nil)
            }

            Button("Check for Updates…") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                AppUpdateService.shared.checkForUpdates()
            }

            Divider()

            Button("DocNest Help") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                HelpWindowController.shared.showWindow(nil)
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
        }
        CommandGroup(replacing: .appSettings) {
            Button("Settings…") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                AppSettingsController.shared.show()
            }
            .keyboardShortcut(",", modifiers: [.command])
        }
        CommandGroup(replacing: .newItem) {
            Button("Create Library") {
                librarySession?.createLibrary()
            }
            Button("Open Library") {
                librarySession?.openLibrary()
            }
            Divider()
            Button("Show in Finder") {
                if let url = librarySession?.selectedLibraryURL {
                    NSWorkspace.shared.activateFileViewerSelecting([url])
                }
            }
            .disabled(librarySession?.selectedLibraryURL == nil)
            Divider()
            Button("Close Library") {
                librarySession?.closeLibrary()
            }
            .disabled(librarySession?.selectedLibraryURL == nil)
        }
        CommandGroup(replacing: .pasteboard) {
            Button("Paste") {
                pasteDocumentsAction?()
            }
            .keyboardShortcut("v", modifiers: [.command])
            .disabled(pasteDocumentsAction == nil)
        }
        CommandGroup(replacing: .importExport) {
            Button("Export\u{2026}") {
                exportDocumentsAction?()
            }
            .keyboardShortcut("e", modifiers: [.command, .shift])
            .disabled(exportDocumentsAction == nil)
        }
        CommandGroup(replacing: .textEditing) {
            Button("Find") {
                NotificationCenter.default.post(name: .docNestFocusSearch, object: nil)
            }
            .keyboardShortcut("f", modifiers: [.command])

            Button("Assign Labels") {
                NotificationCenter.default.post(name: .docNestQuickLabelPicker, object: nil)
            }
            .keyboardShortcut("l", modifiers: [.command])

            Button("Select All") {
                selectAllDocumentsAction?()
            }
            .keyboardShortcut("a", modifiers: [.command])
            .disabled(selectAllDocumentsAction == nil)
        }
        CommandGroup(replacing: .help) {
            Button("DocNest Help") {
                NSApplication.shared.activate(ignoringOtherApps: true)
                HelpWindowController.shared.showWindow(nil)
            }
            .keyboardShortcut("?", modifiers: [.command, .shift])
        }
        CommandMenu("View") {
            Button(isInspectorCollapsed == true ? "Show Details" : "Hide Details") {
                toggleInspectorAction?()
            }
            .keyboardShortcut("d", modifiers: [.control])
            .disabled(toggleInspectorAction == nil)
        }
    }
}

// MARK: - Appearance

enum AppearanceMode: String, CaseIterable, Identifiable {
    case system
    case light
    case dark

    var id: String { rawValue }

    var label: String {
        switch self {
        case .system: "System"
        case .light:  "Light"
        case .dark:   "Dark"
        }
    }

    var appAppearance: NSAppearance? {
        switch self {
        case .system:
            nil
        case .light:
            NSAppearance(named: .aqua)
        case .dark:
            NSAppearance(named: .darkAqua)
        }
    }
}

// MARK: - Root View

private struct AppRootView: View {
    @StateObject private var librarySession = LibrarySessionController()
    @AppStorage("appearanceMode") private var appearanceMode: AppearanceMode = .system

    private func applyAppearance(_ mode: AppearanceMode) {
        NSApp.appearance = mode.appAppearance
        for window in NSApp.windows {
            window.appearance = mode.appAppearance
        }
    }

    @ViewBuilder
    private func appearanceMenuLabel(for mode: AppearanceMode) -> some View {
        if appearanceMode == mode {
            Label(mode.label, systemImage: "checkmark")
        } else {
            Text(mode.label)
        }
    }

    var body: some View {
        Group {
            if let libraryURL = librarySession.selectedLibraryURL,
               let modelContainer = librarySession.modelContainer {
                RootView(libraryURL: libraryURL, librarySession: librarySession)
                    .modelContainer(modelContainer)
                    .accessibilityIdentifier("library-open-root")
            } else {
                closedLibraryContent
                    .accessibilityIdentifier("library-closed-root")
            }
        }
        .onAppear {
            applyAppearance(appearanceMode)
            AboutStatisticsProvider.shared.controller = librarySession
        }
        .onChange(of: appearanceMode) { _, newMode in
            applyAppearance(newMode)
        }
        .focusedSceneValue(\.librarySession, librarySession)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    ForEach(AppearanceMode.allCases) { mode in
                        Button {
                            appearanceMode = mode
                        } label: {
                            appearanceMenuLabel(for: mode)
                        }
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .help("Switch appearance")
            }
        }
        .onOpenURL { url in
            if url.pathExtension.caseInsensitiveCompare("docnestlibrary") == .orderedSame {
                librarySession.openLibraryFromFinder(url)
            } else {
                librarySession.queueImportURLs([url])
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: ServicesProvider.didReceiveFilesNotification)) { notification in
            if let urls = notification.object as? [URL], !urls.isEmpty {
                librarySession.queueImportURLs(urls)
            }
        }
        .onChange(of: librarySession.selectedLibraryURL) { _, _ in
            AboutStatisticsProvider.shared.controller = librarySession
        }
        .task {
            librarySession.restorePersistedLibrary()
        }
        .alert("Library Error", isPresented: libraryErrorBinding) {
            Button("Open Library") {
                librarySession.libraryErrorMessage = nil
                librarySession.openLibrary()
            }
            Button("Create Library") {
                librarySession.libraryErrorMessage = nil
                librarySession.createLibrary()
            }
            Button("Cancel", role: .cancel) {
                librarySession.libraryErrorMessage = nil
            }
        } message: {
            Text(librarySession.libraryErrorMessage ?? "Unknown library error.")
        }
    }

    // MARK: - Closed-library three-panel layout (req 10.5)

    @State private var isClosedLibraryDropTargeted = false

    private var closedLibraryContent: some View {
        HStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    closedSidebarSection("Library") {
                        Text("No library open")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    closedSidebarSection("Labels") {
                        Text("No labels")
                            .font(.system(size: 13, weight: .regular))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                }
            }
            .frame(width: AppSplitViewLayout.sidebarWidth)
            .fixedSize(horizontal: true, vertical: false)

            Divider()

            ZStack {
                ContentUnavailableView {
                    Label("No Library Open", systemImage: "books.vertical")
                } description: {
                    Text("Create a DocNest library or open an existing one before importing documents.")
                } actions: {
                    HStack(spacing: 12) {
                        Button("Create Library", action: librarySession.createLibrary)
                        Button("Open Library", action: librarySession.openLibrary)
                    }
                }

                if isClosedLibraryDropTargeted {
                    DocumentImportDropOverlay(
                        title: "Open a Library First",
                        message: "Create or open a DocNest library before dropping PDFs or folders into the app."
                    )
                    .padding(20)
                }
            }
            .frame(maxWidth: .infinity)
            .dropDestination(for: URL.self) { urls, _ in
                handleDroppedURLsWithoutLibrary(urls)
            } isTargeted: { isTargeted in
                isClosedLibraryDropTargeted = isTargeted
            }

            Divider()

            ContentUnavailableView(
                "No Document Selected",
                systemImage: "doc.text",
                description: Text("Open a library and select a document to see its details.")
            )
            .frame(width: AppSplitViewLayout.inspectorWidth)
        }
        .padding([.top, .bottom, .trailing], AppSplitViewLayout.windowContentInset)
    }

    private func closedSidebarSection<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.secondary)
                .textCase(.uppercase)
                .padding(.horizontal, 16)
                .padding(.top, 12)
                .padding(.bottom, 4)

            content()
        }
    }

    // MARK: - Helpers

    private var libraryErrorBinding: Binding<Bool> {
        Binding(
            get: { librarySession.libraryErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    librarySession.libraryErrorMessage = nil
                }
            }
        )
    }

    private func handleDroppedURLsWithoutLibrary(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else {
            return false
        }

        if ImportPDFDocumentsUseCase.containsImportableDocuments(in: urls) {
            librarySession.libraryErrorMessage = "Create or open a DocNest library before importing files via drag and drop."
            return true
        }

        return false
    }
}

@MainActor
/// Owns the currently selected library session across app launches.
///
/// The session controller bridges app lifecycle events and library access:
/// it restores the last valid library, creates or opens new libraries, holds
/// the active `ModelContainer`, and queues import URLs until a library becomes
/// available.
final class LibrarySessionController: ObservableObject {
    private static let logger = Logger(subsystem: "com.kaps.docnest", category: "LibrarySession")
    private static let isRunningUnderTests = ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil
    @Published private(set) var selectedLibraryURL: URL?
    @Published private(set) var modelContainer: ModelContainer?
    @Published var libraryErrorMessage: String?
    @Published var pendingImportURLs: [URL] = []

    private var lockHeartbeatTimer: Timer?
    private static let lockHeartbeatInterval: TimeInterval = 30

    private var terminationObserver: Any?
    private var activeLibraryAccessSession: DocumentLibraryService.LibraryAccessSession?
    private var integrityRefreshTask: Task<Void, Never>?

    func queueImportURLs(_ urls: [URL]) {
        pendingImportURLs.append(contentsOf: urls)
    }

    func drainPendingImportURLs() -> [URL] {
        let urls = pendingImportURLs
        pendingImportURLs.removeAll()
        return urls
    }

    func restorePersistedLibrary() {
        guard !Self.isRunningUnderTests else {
            return
        }

        guard selectedLibraryURL == nil,
              let accessSession = DocumentLibraryService.restorePersistedLibraryAccess() else {
            return
        }

        openValidatedLibrary(accessSession)
    }

    func createLibrary() {
        guard let url = DocumentLibraryService.promptForNewLibraryURL() else {
            return
        }

        do {
            let libraryURL = try DocumentLibraryService.createLibrary(at: url)
            openValidatedLibrary(DocumentLibraryService.accessLibrary(at: libraryURL))
        } catch {
            libraryErrorMessage = error.localizedDescription
        }
    }

    func openLibrary() {
        guard let url = DocumentLibraryService.promptForExistingLibrary() else {
            return
        }

        openValidatedLibrary(DocumentLibraryService.accessLibrary(at: url))
    }

    func openLibraryFromFinder(_ url: URL) {
        openValidatedLibrary(DocumentLibraryService.accessLibrary(at: url))
    }

    func closeLibrary() {
        integrityRefreshTask?.cancel()
        integrityRefreshTask = nil
        stopLockHeartbeat()
        if let url = selectedLibraryURL {
            DocumentLibraryService.releaseLock(for: url)
        }
        if let accessSession = activeLibraryAccessSession,
           accessSession.startedAccessingSecurityScope {
            accessSession.url.stopAccessingSecurityScopedResource()
        }
        activeLibraryAccessSession = nil
        selectedLibraryURL = nil
        modelContainer = nil
    }

    private func openValidatedLibrary(_ accessSession: DocumentLibraryService.LibraryAccessSession) {
        do {
            let packageRepair = try DocumentLibraryService.repairLibraryPackageIfNeeded(at: accessSession.url)
            let (validatedURL, manifest) = try DocumentLibraryService.validateLibrary(at: accessSession.url)
            let migration = try DocumentLibraryService.migrateLibraryIfNeeded(at: validatedURL, manifest: manifest)
            try DocumentLibraryService.acquireLock(for: validatedURL)
            try openLibrary(
                DocumentLibraryService.LibraryAccessSession(
                    url: validatedURL,
                    startedAccessingSecurityScope: accessSession.startedAccessingSecurityScope
                ),
                manifest: DocumentLibraryManifest(
                    formatVersion: migration.toFormatVersion,
                    createdAt: manifest.createdAt
                ),
                migration: migration,
                packageRepair: packageRepair
            )
        } catch {
            if accessSession.startedAccessingSecurityScope {
                accessSession.url.stopAccessingSecurityScopedResource()
            }
            libraryErrorMessage = error.localizedDescription
        }
    }

    private func openLibrary(
        _ accessSession: DocumentLibraryService.LibraryAccessSession,
        manifest: DocumentLibraryManifest,
        migration: LibraryMigrationResult,
        packageRepair: LibraryRepairResult
    ) throws {
        let container = try DocumentLibraryService.openModelContainer(for: accessSession.url)
        if let currentURL = selectedLibraryURL,
           currentURL != accessSession.url {
            closeLibrary()
        }
        modelContainer = container
        selectedLibraryURL = accessSession.url
        activeLibraryAccessSession = accessSession
        DocumentLibraryService.persistLibraryURL(accessSession.url)
        libraryErrorMessage = nil
        startLockHeartbeat(for: accessSession.url)
        observeAppTermination(for: accessSession.url)
        integrityRefreshTask?.cancel()
        integrityRefreshTask = Task { [libraryURL = accessSession.url, manifest, migration, packageRepair] in
            do {
                _ = try await DocumentLibraryService.refreshIntegrityArtifacts(
                    for: libraryURL,
                    manifest: manifest,
                    migration: migration,
                    packageRepair: packageRepair
                )
            } catch is CancellationError {
                return
            } catch {
                Self.logger.error("Failed to refresh integrity artifacts: \(error.localizedDescription, privacy: .public)")
            }
        }
    }

    // MARK: - Lock Heartbeat

    private func startLockHeartbeat(for libraryURL: URL) {
        stopLockHeartbeat()
        lockHeartbeatTimer = Timer.scheduledTimer(
            withTimeInterval: Self.lockHeartbeatInterval,
            repeats: true
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard self?.selectedLibraryURL == libraryURL else { return }
                try? DocumentLibraryService.refreshLock(for: libraryURL)
            }
        }
    }

    private func stopLockHeartbeat() {
        lockHeartbeatTimer?.invalidate()
        lockHeartbeatTimer = nil
    }

    // MARK: - Library Statistics

    struct LibraryStatistics {
        let path: String
        let documentCount: Int
        let totalFileSize: Int64
        let libraryPackageSize: Int64

        var formattedTotalFileSize: String {
            ByteCountFormatter.string(fromByteCount: totalFileSize, countStyle: .file)
        }

        var formattedPackageSize: String {
            ByteCountFormatter.string(fromByteCount: libraryPackageSize, countStyle: .file)
        }
    }

    func libraryStatistics() async -> LibraryStatistics? {
        guard let url = selectedLibraryURL,
              let container = modelContainer else {
            return nil
        }

        let context = container.mainContext
        let descriptor = FetchDescriptor<DocumentRecord>()
        let documents = (try? context.fetch(descriptor)) ?? []

        let totalFileSize = documents.reduce(Int64(0)) { $0 + $1.fileSize }
        let documentCount = documents.count
        let path = url.path

        let packageSize = await Task.detached(priority: .utility) {
            var size: Int64 = 0
            guard let enumerator = FileManager.default.enumerator(
                at: url,
                includingPropertiesForKeys: [.fileSizeKey],
                options: [.skipsHiddenFiles]
            ) else {
                return size
            }
            while let fileURL = enumerator.nextObject() as? URL {
                let fileSize = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                size += Int64(fileSize)
            }
            return size
        }.value

        return LibraryStatistics(
            path: path,
            documentCount: documentCount,
            totalFileSize: totalFileSize,
            libraryPackageSize: packageSize
        )
    }

    private func observeAppTermination(for libraryURL: URL) {
        if let existing = terminationObserver {
            NotificationCenter.default.removeObserver(existing)
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification,
            object: nil,
            queue: .main
        ) { _ in
            DocumentLibraryService.releaseLock(for: libraryURL)
        }
    }
}
