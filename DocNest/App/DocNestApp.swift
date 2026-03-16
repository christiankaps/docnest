import AppKit
import SwiftUI
import SwiftData

// MARK: - Focused Value for Library Session

private struct LibrarySessionKey: FocusedValueKey {
    typealias Value = LibrarySessionController
}

private struct ExportDocumentsActionKey: FocusedValueKey {
    typealias Value = () -> Void
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
}

@main
struct DocNestApp: App {
    @FocusedValue(\.librarySession) private var librarySession
    @FocusedValue(\.exportDocumentsAction) private var exportDocumentsAction

    init() {
        NSWindow.allowsAutomaticWindowTabbing = false
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
            CommandGroup(replacing: .pasteboard) { }
            CommandGroup(replacing: .undoRedo) { }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .importExport) {
                Button("Export\u{2026}") {
                    exportDocumentsAction?()
                }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(exportDocumentsAction == nil)
            }
            CommandGroup(replacing: .printItem) { }
            CommandGroup(replacing: .textEditing) { }
            CommandGroup(replacing: .textFormatting) { }
            CommandGroup(replacing: .help) { }
            CommandMenu("Edit") {
                Button("Find") {
                    NotificationCenter.default.post(name: .docNestFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
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

    var body: some View {
        Group {
            if let libraryURL = librarySession.selectedLibraryURL,
               let modelContainer = librarySession.modelContainer {
                RootView(libraryURL: libraryURL)
                    .modelContainer(modelContainer)
                    .accessibilityIdentifier("library-open-root")
            } else {
                closedLibraryContent
                    .accessibilityIdentifier("library-closed-root")
            }
        }
        .onAppear {
            applyAppearance(appearanceMode)
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
                            HStack {
                                Text(mode.label)
                                if appearanceMode == mode {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                } label: {
                    Label("Appearance", systemImage: "circle.lefthalf.filled")
                }
                .help("Switch appearance")
            }
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
                            .font(.system(size: 13, weight: .regular, design: .rounded))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 6)
                    }
                    closedSidebarSection("Labels") {
                        Text("No labels")
                            .font(.system(size: 13, weight: .regular, design: .rounded))
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
                        message: "Create or open a DocNest library before dropping PDFs into the app."
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
            librarySession.libraryErrorMessage = "Create or open a DocNest library before importing PDFs via drag and drop."
            return true
        }

        return false
    }
}

@MainActor
final class LibrarySessionController: ObservableObject {
    @Published private(set) var selectedLibraryURL: URL?
    @Published private(set) var modelContainer: ModelContainer?
    @Published var libraryErrorMessage: String?

    func restorePersistedLibrary() {
        guard selectedLibraryURL == nil,
              let persistedLibraryURL = DocumentLibraryService.restorePersistedLibraryURL() else {
            return
        }

        openValidatedLibrary(at: persistedLibraryURL)
    }

    func createLibrary() {
        guard let url = DocumentLibraryService.promptForNewLibraryURL() else {
            return
        }

        do {
            let libraryURL = try DocumentLibraryService.createLibrary(at: url)
            try openLibrary(at: libraryURL)
        } catch {
            libraryErrorMessage = error.localizedDescription
        }
    }

    func openLibrary() {
        guard let url = DocumentLibraryService.promptForExistingLibrary() else {
            return
        }

        openValidatedLibrary(at: url)
    }

    func closeLibrary() {
        selectedLibraryURL = nil
        modelContainer = nil
    }

    private func openValidatedLibrary(at url: URL) {
        do {
            let validatedURL = try DocumentLibraryService.validateLibrary(at: url)
            try openLibrary(at: validatedURL)
        } catch {
            closeLibrary()
            DocumentLibraryService.persistLibraryURL(nil)
            libraryErrorMessage = error.localizedDescription
        }
    }

    private func openLibrary(at libraryURL: URL) throws {
        modelContainer = try DocumentLibraryService.openModelContainer(for: libraryURL)
        selectedLibraryURL = libraryURL
        DocumentLibraryService.persistLibraryURL(libraryURL)
        libraryErrorMessage = nil
    }
}