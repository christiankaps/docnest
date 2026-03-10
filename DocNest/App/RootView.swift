import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    let libraryURL: URL
    @State private var selectedSection: LibrarySection = .allDocuments
    @State private var selectedLabelIDs: Set<PersistentIdentifier> = []
    @State private var selectedDocumentID: PersistentIdentifier?
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var isShowingLabelManager = false
    @State private var importSummaryMessage: String?
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DocumentRecord.importedAt, order: .reverse)
    private var allDocuments: [DocumentRecord]

    @Query(sort: \LabelTag.name, order: .forward)
    private var allLabels: [LabelTag]

    private var recentDocuments: [DocumentRecord] {
        Array(allDocuments.prefix(10))
    }

    private var filteredDocuments: [DocumentRecord] {
        let sectionDocuments: [DocumentRecord] = switch selectedSection {
        case .allDocuments:
            allDocuments
        case .recent:
            recentDocuments
        case .needsLabels:
            allDocuments.filter { $0.labels.isEmpty }
        }

        return sectionDocuments.filter {
            ManageLabelsUseCase.matchingAllSelectedLabels($0, selectedLabelIDs: selectedLabelIDs)
        }
    }

    private var selectedDocument: DocumentRecord? {
        filteredDocuments.first { $0.persistentModelID == selectedDocumentID } ?? filteredDocuments.first
    }

    var body: some View {
        NavigationSplitView {
            LibrarySidebarView(
                selectedSection: $selectedSection,
                labels: allLabels,
                selectedLabelIDs: $selectedLabelIDs
            )
        } content: {
            ZStack {
                DocumentListView(
                    documents: filteredDocuments,
                    selectedDocumentID: $selectedDocumentID
                )

                if isDropTargeted {
                    DocumentImportDropOverlay(
                        title: "Drop PDFs to Import",
                        message: "Files will be copied into the open library and processed with the same rules as the import dialog."
                    )
                    .padding(20)
                }
            }
            .dropDestination(for: URL.self) { urls, _ in
                handleDroppedURLs(urls)
            } isTargeted: { isTargeted in
                isDropTargeted = isTargeted
            }
        } detail: {
            DocumentInspectorView(
                document: selectedDocument,
                libraryURL: libraryURL,
                onManageLabels: {
                    isShowingLabelManager = true
                }
            )
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

            ToolbarItem {
                Button {
                    isShowingLabelManager = true
                } label: {
                    Label("Manage Labels", systemImage: "tag")
                }
            }
        }
        .sheet(isPresented: $isShowingLabelManager) {
            LabelManagementView()
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
        .onChange(of: allLabels.map(\.persistentModelID)) { _, labelIDs in
            selectedLabelIDs.formIntersection(Set(labelIDs))
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
        guard case .success(let urls) = result else {
            importSummaryMessage = "The selected files could not be read."
            return
        }

        importDocuments(from: urls)
    }

    private func handleDroppedURLs(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else {
            return false
        }

        importDocuments(from: urls)
        return true
    }

    private func importDocuments(from urls: [URL]) {
        guard !urls.isEmpty else {
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

struct DocumentImportDropOverlay: View {
    let title: String
    let message: String

    var body: some View {
        RoundedRectangle(cornerRadius: 18)
            .fill(.ultraThinMaterial)
            .overlay {
                RoundedRectangle(cornerRadius: 18)
                    .strokeBorder(.tint.opacity(0.55), style: StrokeStyle(lineWidth: 2, dash: [8, 6]))
            }
            .overlay {
                VStack(spacing: 12) {
                    Image(systemName: "square.and.arrow.down.on.square.fill")
                        .font(.system(size: 30))
                        .foregroundStyle(.tint)
                    Text(title)
                        .font(.headline)
                    Text(message)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .frame(maxWidth: 360)
                }
                .padding(28)
            }
            .allowsHitTesting(false)
    }
}

#Preview {
    RootView(libraryURL: URL(fileURLWithPath: "/tmp/preview.docnestlibrary"))
        .modelContainer(for: DocumentRecord.self, inMemory: true)
}