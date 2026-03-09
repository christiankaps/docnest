import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit

struct RootView: View {
    @State private var selectedSection: LibrarySection = .allDocuments
    @State private var selectedDocumentID: PersistentIdentifier?
    @State private var isImporting = false
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DocumentRecord.importedAt, order: .reverse)
    private var allDocuments: [DocumentRecord]

    private var filteredDocuments: [DocumentRecord] {
        switch selectedSection {
        case .allDocuments:
            allDocuments
        case .recent:
            allDocuments
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
            DocumentInspectorView(document: selectedDocument)
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
        .task {
            try? SampleDataSeeder.seedIfNeeded(using: modelContext)
        }
    }

    private func handleImportResult(_ result: Result<[URL], Error>) {
        guard let urls = try? result.get() else { return }
        for url in urls {
            guard url.startAccessingSecurityScopedResource() else { continue }
            defer { url.stopAccessingSecurityScopedResource() }

            let docID = UUID()
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
                from: url, documentID: docID
            ) else { continue }

            let record = DocumentRecord(
                id: docID,
                originalFileName: fileName,
                title: title,
                importedAt: .now,
                pageCount: pageCount,
                storedFilePath: storedPath
            )
            modelContext.insert(record)
        }
        try? modelContext.save()
    }
}

#Preview {
    RootView()
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}