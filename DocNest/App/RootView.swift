import SwiftUI

struct RootView: View {
    @State private var selectedSection: LibrarySection = .allDocuments
    @State private var selectedDocumentID: DocumentRecord.ID?

    private let documents = DocumentRecord.samples

    private var filteredDocuments: [DocumentRecord] {
        switch selectedSection {
        case .allDocuments:
            documents
        case .recent:
            documents.sorted { $0.importedAt > $1.importedAt }
        case .needsLabels:
            documents.filter { $0.labels.isEmpty }
        }
    }

    private var selectedDocument: DocumentRecord? {
        filteredDocuments.first { $0.id == selectedDocumentID } ?? filteredDocuments.first
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
    }
}

#Preview {
    RootView()
}