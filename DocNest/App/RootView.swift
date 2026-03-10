import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    let libraryURL: URL
    @State private var selectedSection: LibrarySection = .allDocuments
    @State private var selectedDocumentID: PersistentIdentifier?
    @State private var isImporting = false
    @State private var importSummaryMessage: String?
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DocumentRecord.importedAt, order: .reverse)
    private var allDocuments: [DocumentRecord]

    private var recentDocuments: [DocumentRecord] {
        Array(allDocuments.prefix(10))
    }

    private var filteredDocuments: [DocumentRecord] {
        switch selectedSection {
        case .allDocuments:
            allDocuments
        case .recent:
            recentDocuments
        case .needsLabels:
            allDocuments.filter { $0.labels.isEmpty }
        }
    }

    private var selectedDocument: DocumentRecord? {
        filteredDocuments.first { $0.persistentModelID == selectedDocumentID } ?? filteredDocuments.first
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(selectedSection: $selectedSection)
        } content: {
            DocumentListView(
                documents: filteredDocuments,
                selectedDocumentID: $selectedDocumentID
            )
        } detail: {
            DocumentInspectorView(document: selectedDocument, libraryURL: libraryURL)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [.pdf],
            allowsMultipleSelection: true
        ) { result in
            handleImportResult(result)
        }
        .alert("Import Summary", isPresented: importSummaryBinding) {
            Button("OK", role: .cancel) {
                importSummaryMessage = nil
            }
        } message: {
            Text(importSummaryMessage ?? "")
        }
    }

    private var importSummaryBinding: Binding<Bool> {
        Binding(
            get: { importSummaryMessage != nil },
            set: { newValue in
                if !newValue {
                    importSummaryMessage = nil
                }
            }
        )
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get() else {
            importSummaryMessage = "The selected files could not be read."
            return
        }

        let importResult = ImportPDFDocumentsUseCase.execute(
            urls: urls,
            into: libraryURL,
            using: modelContext
        )

        if importResult.hasUserMessage {
            importSummaryMessage = importResult.summaryMessage
        }
    }
}

#Preview {
    RootView(libraryURL: URL(fileURLWithPath: "/tmp/preview.docnestlibrary"))
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}