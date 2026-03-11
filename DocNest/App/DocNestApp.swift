import SwiftUI
import SwiftData

@main
struct DocNestApp: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
                .frame(minWidth: 960, minHeight: 600)
        }
        .defaultSize(width: 1280, height: 800)
        .windowResizability(.contentMinSize)
    }
}

private struct AppRootView: View {
    @StateObject private var librarySession = LibrarySessionController()
    @State private var isClosedLibraryDropTargeted = false

    var body: some View {
        Group {
            if let libraryURL = librarySession.selectedLibraryURL,
               let modelContainer = librarySession.modelContainer {
                RootView(libraryURL: libraryURL)
                    .modelContainer(modelContainer)
                    .accessibilityIdentifier("library-open-root")
            } else {
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
                .overlay {
                    if isClosedLibraryDropTargeted {
                        DocumentImportDropOverlay(
                            title: "Open a Library First",
                            message: "Create or open a DocNest library before dropping PDFs into the app."
                        )
                        .padding(32)
                    }
                }
                .dropDestination(for: URL.self) { urls, _ in
                    handleDroppedURLsWithoutLibrary(urls)
                } isTargeted: { isTargeted in
                    isClosedLibraryDropTargeted = isTargeted
                }
                .accessibilityIdentifier("library-closed-root")
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
            Button("OK", role: .cancel) {
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