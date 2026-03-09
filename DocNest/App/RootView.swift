import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit

struct RootView: View {
    @State private var selectedSection: LibrarySection = .allDocuments
    @State private var selectedDocumentID: PersistentIdentifier?
    @State private var isImporting = false
    @State private var selectedLibraryURL: URL?
    @State private var libraryErrorMessage: String?
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DocumentRecord.importedAt, order: .reverse)
    private var allDocuments: [DocumentRecord]

    private var libraryDocuments: [DocumentRecord] {
        guard let selectedLibraryURL else {
            return []
        }

        return allDocuments.filter { $0.libraryPath == selectedLibraryURL.path }
    }

    private var filteredDocuments: [DocumentRecord] {
        switch selectedSection {
        case .allDocuments:
            libraryDocuments
        case .recent:
            libraryDocuments
        case .needsLabels:
            libraryDocuments.filter { $0.labels.isEmpty }
        }
    }

    private var selectedDocument: DocumentRecord? {
        filteredDocuments.first { $0.persistentModelID == selectedDocumentID } ?? filteredDocuments.first
    }

    var body: some View {
        Group {
            if selectedLibraryURL != nil {
                NavigationSplitView {
                    LibrarySidebarView(selectedSection: $selectedSection)
                } content: {
                    DocumentListView(
                        documents: filteredDocuments,
                        selectedDocumentID: $selectedDocumentID
                    )
                } detail: {
                    DocumentInspectorView(document: selectedDocument, libraryURL: selectedLibraryURL)
                }
            } else {
                libraryEmptyState
            }
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Menu("Library") {
                    Button("Create Library", action: createLibrary)
                    Button("Open Library", action: openLibrary)
                    if selectedLibraryURL != nil {
                        Button("Close Library", role: .destructive, action: closeLibrary)
                    }
                }
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
                .disabled(selectedLibraryURL == nil)
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result)
        }
        .task {
            restoreLibrarySelection()
        }
        .alert("Library Error", isPresented: libraryErrorBinding) {
            Button("OK", role: .cancel) {
                libraryErrorMessage = nil
            }
        } message: {
            Text(libraryErrorMessage ?? "Unknown library error.")
        }
    }

    private var libraryEmptyState: some View {
        ContentUnavailableView {
            Label("No Library Open", systemImage: "books.vertical")
        } description: {
            Text("Create a DocNest library or open an existing one before importing documents.")
        } actions: {
            HStack(spacing: 12) {
                Button("Create Library", action: createLibrary)
                Button("Open Library", action: openLibrary)
            }
        }
    }

    private var libraryErrorBinding: Binding<Bool> {
        Binding(
            get: { libraryErrorMessage != nil },
            set: { newValue in
                if !newValue {
                    libraryErrorMessage = nil
                }
            }
        )
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        guard let libraryURL = selectedLibraryURL,
              let urls = try? result.get() else { return }

        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            let docID = UUID()
            let importedAt = Date.now
            let fileName = url.lastPathComponent
            let title = url.deletingPathExtension().lastPathComponent
                .replacingOccurrences(of: "-", with: " ")
                .replacingOccurrences(of: "_", with: " ")
                .localizedCapitalized

            var pageCount = 0
            if let pdfDoc = PDFDocument(url: url) {
                pageCount = pdfDoc.pageCount
            }

            guard let storedPath = try? DocumentStorageService.copyToStorage(
                from: url,
                documentID: docID,
                importedAt: importedAt,
                libraryURL: libraryURL
            ) else { continue }

            let record = DocumentRecord(
                id: docID,
                libraryPath: libraryURL.path,
                originalFileName: fileName,
                title: title,
                importedAt: importedAt,
                pageCount: pageCount,
                storedFilePath: storedPath
            )
            modelContext.insert(record)
        }

        try? modelContext.save()
    }

    private func restoreLibrarySelection() {
        guard selectedLibraryURL == nil,
              let persistedLibraryURL = DocumentLibraryService.restorePersistedLibraryURL() else {
            return
        }

        do {
            selectedLibraryURL = try DocumentLibraryService.validateLibrary(at: persistedLibraryURL)
        } catch {
            DocumentLibraryService.persistLibraryURL(nil)
            libraryErrorMessage = error.localizedDescription
        }
    }

    private func createLibrary() {
        guard let url = DocumentLibraryService.promptForNewLibraryURL() else {
            return
        }

        do {
            selectedLibraryURL = try DocumentLibraryService.createLibrary(at: url)
            selectedDocumentID = nil
        } catch {
            libraryErrorMessage = error.localizedDescription
        }
    }

    private func openLibrary() {
        guard let url = DocumentLibraryService.promptForExistingLibrary() else {
            return
        }

        do {
            selectedLibraryURL = try DocumentLibraryService.validateLibrary(at: url)
            selectedDocumentID = nil
        } catch {
            libraryErrorMessage = error.localizedDescription
        }
    }

    private func closeLibrary() {
        selectedLibraryURL = nil
        selectedDocumentID = nil
        DocumentLibraryService.persistLibraryURL(nil)
    }
}

#Preview {
    RootView()
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}