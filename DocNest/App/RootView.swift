import SwiftUI
import SwiftData

struct RootView: View {
    @State private var selectedSection: LibrarySection = .allDocuments
    @State private var selectedDocumentID: PersistentIdentifier?
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
        .task {
            try? SampleDataSeeder.seedIfNeeded(using: modelContext)
        }
    }
}

#Preview {
    RootView()
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}