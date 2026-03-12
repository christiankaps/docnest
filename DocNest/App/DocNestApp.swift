import SwiftUI
import SwiftData

@main
struct DocNestApp: App {
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
            CommandGroup(replacing: .newItem) { }
            CommandGroup(after: .pasteboard) {
                Button("Find") {
                    NotificationCenter.default.post(name: .docNestFocusSearch, object: nil)
                }
                .keyboardShortcut("f", modifiers: [.command])
            }
            CommandGroup(replacing: .saveItem) { }
            CommandGroup(replacing: .importExport) { }
            CommandGroup(replacing: .printItem) { }
        }
    }
}

private struct AppRootView: View {
    @StateObject private var librarySession = LibrarySessionController()
    @State private var isClosedLibraryDropTargeted = false
    @State private var columnVisibility: NavigationSplitViewVisibility = .all

    var body: some View {
        Group {
            if let libraryURL = librarySession.selectedLibraryURL,
               let modelContainer = librarySession.modelContainer {
                RootView(libraryURL: libraryURL)
                    .modelContainer(modelContainer)
                    .accessibilityIdentifier("library-open-root")
            } else {
                NavigationSplitView(columnVisibility: $columnVisibility) {
                    List {
                        Section("Library") {
                            Label("All Documents", systemImage: "doc.richtext")
                            Label("Recent Imports", systemImage: "clock")
                            Label("Needs Labels", systemImage: "tag.slash")
                        }

                        Section("Label Filters") {
                            Text("No labels yet")
                                .font(AppTypography.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .navigationTitle("Library")
                    .navigationSplitViewColumnWidth(
                        min: AppSplitViewLayout.sidebarWidth,
                        ideal: AppSplitViewLayout.sidebarWidth,
                        max: AppSplitViewLayout.sidebarWidth
                    )
                } content: {
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
                    .dropDestination(for: URL.self) { urls, _ in
                        handleDroppedURLsWithoutLibrary(urls)
                    } isTargeted: { isTargeted in
                        isClosedLibraryDropTargeted = isTargeted
                    }
                    .navigationTitle("Documents")
                    .navigationSplitViewColumnWidth(
                        min: AppSplitViewLayout.closedLibraryContentMinWidth,
                        ideal: AppSplitViewLayout.closedLibraryContentIdealWidth
                    )
                } detail: {
                    ContentUnavailableView(
                        "No Document Selected",
                        systemImage: "doc.text",
                        description: Text("Open or create a library to inspect document details and preview PDFs.")
                    )
                    .navigationTitle("Preview")
                    .navigationSplitViewColumnWidth(
                        min: AppSplitViewLayout.inspectorWidth,
                        ideal: AppSplitViewLayout.inspectorWidth,
                        max: AppSplitViewLayout.inspectorWidth
                    )
                }
                .navigationSplitViewStyle(.balanced)
                .accessibilityIdentifier("library-closed-root")
                .onAppear {
                    columnVisibility = .all
                }
            }
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu("Library") {
                    Button("Create Library", action: librarySession.createLibrary)
                    Button("Open Library", action: librarySession.openLibrary)
                    if librarySession.selectedLibraryURL != nil {
                        Button("Close Library", role: .destructive, action: librarySession.closeLibrary)
                    }
                }
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
private final class LibrarySessionController: ObservableObject {
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