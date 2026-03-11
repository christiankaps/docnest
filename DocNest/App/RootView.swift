import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    let libraryURL: URL
    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedSection: LibrarySection = .allDocuments
    @State private var selectedLabelIDs: Set<PersistentIdentifier> = []
    @State private var selectedDocumentIDs: Set<PersistentIdentifier> = []
    @State private var searchText = ""
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

        return SearchDocumentsUseCase.filter(
            sectionDocuments,
            query: searchText,
            selectedLabelIDs: selectedLabelIDs
        )
    }

    private var selectedDocuments: [DocumentRecord] {
        let explicitSelection = filteredDocuments.filter { selectedDocumentIDs.contains($0.persistentModelID) }

        if !explicitSelection.isEmpty {
            return explicitSelection
        }

        return filteredDocuments.first.map { [$0] } ?? []
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebarView(
                selectedSection: $selectedSection,
                labels: allLabels,
                selectedLabelIDs: $selectedLabelIDs
            )
            .navigationSplitViewColumnWidth(min: 240, ideal: 260, max: 300)
        } content: {
            ZStack {
                DocumentListView(
                    documents: filteredDocuments,
                    selectedDocumentIDs: $selectedDocumentIDs
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
            .navigationSplitViewColumnWidth(min: 560, ideal: 740)
        } detail: {
            DocumentInspectorView(
                documents: selectedDocuments,
                libraryURL: libraryURL,
                onManageLabels: {
                    isShowingLabelManager = true
                }
            )
            .navigationSplitViewColumnWidth(min: 380, ideal: 520, max: 760)
        }
        .searchable(text: $searchText, prompt: "Search title, file name, or labels")
        .onAppear {
            columnVisibility = .all
        }
        .toolbar {
            ToolbarItem(placement: .navigation) {
                Button {
                    withAnimation {
                        columnVisibility = columnVisibility == .all ? .doubleColumn : .all
                    }
                } label: {
                    Label("Toggle Sidebar", systemImage: "sidebar.leading")
                }
            }

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
        .onChange(of: filteredDocuments.map(\.persistentModelID)) { _, documentIDs in
            selectedDocumentIDs.formIntersection(Set(documentIDs))
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