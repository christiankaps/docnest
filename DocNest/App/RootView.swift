import SwiftUI
import SwiftData

struct RootView: View {
    let libraryURL: URL

    @State private var coordinator = LibraryCoordinator()
    @State private var thumbnailCache = ThumbnailCache()
    @State private var quickLook = QuickLookCoordinator()

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DocumentRecord.importedAt, order: .reverse)
    private var allDocuments: [DocumentRecord]

    @Query(sort: [SortDescriptor(\LabelTag.sortOrder, order: .forward), SortDescriptor(\LabelTag.name, order: .forward)])
    private var allLabels: [LabelTag]

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebarView()
                .frame(width: AppSplitViewLayout.sidebarWidth)

            Divider()

            documentListPanel
                .frame(minWidth: AppSplitViewLayout.documentListMinWidth)

            Divider()

            DocumentInspectorView(
                documents: coordinator.selectedDocuments,
                libraryURL: libraryURL
            )
            .frame(width: AppSplitViewLayout.inspectorWidth)
        }
        .padding(AppSplitViewLayout.windowContentInset)
        .environment(coordinator)
        .environment(thumbnailCache)
        .environment(quickLook)
        .toolbar { toolbarContent }
        .modifier(RootViewImportModifier(coordinator: coordinator, allDocuments: allDocuments))
        .modifier(RootViewDialogsModifier(coordinator: coordinator, allDocuments: allDocuments))
        .modifier(RootViewChangeHandlers(coordinator: coordinator, allDocuments: allDocuments, allLabels: allLabels))
        .task {
            coordinator.libraryURL = libraryURL
            coordinator.modelContext = modelContext
            coordinator.ingest(allDocuments: allDocuments, allLabels: allLabels)
            await ExtractDocumentTextUseCase.backfillAll(
                documents: allDocuments,
                libraryURL: libraryURL,
                modelContext: modelContext
            )
        }
    }

    private var documentListPanel: some View {
        ZStack {
            DocumentListView()

            if coordinator.isDropTargeted {
                DocumentImportDropOverlay(
                    title: "Drop PDFs to Import",
                    message: "Files will be copied into the open library and processed with the same rules as the import dialog."
                )
                .padding(20)
            }
        }
        .background { QuickLookPanelResponder(coordinator: quickLook) }
        .dropDestination(for: URL.self) { urls, _ in
            handleDroppedURLs(urls)
        } isTargeted: { isTargeted in
            coordinator.isDropTargeted = isTargeted
        }
        .onChange(of: coordinator.cachedShareURLs) {
            quickLook.previewURLs = coordinator.cachedShareURLs
            quickLook.reloadIfVisible()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            SearchToolbarField(
                text: Bindable(coordinator).searchText,
                focusRequestToken: coordinator.searchFocusRequestToken
            )
            .frame(width: 280)
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                coordinator.isImporting = true
            } label: {
                Label("Import", systemImage: "plus")
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Picker("View", selection: Bindable(coordinator).documentListViewMode) {
                Image(systemName: "list.bullet")
                    .tag(DocumentListViewMode.list)
                Image(systemName: "square.grid.2x2")
                    .tag(DocumentListViewMode.thumbnails)
            }
            .pickerStyle(.segmented)
            .frame(width: 60)
            .help("Switch between list and thumbnail view")
        }

        ToolbarItem(placement: .primaryAction) {
            ShareLink(items: coordinator.cachedShareURLs) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(coordinator.cachedShareURLs.isEmpty)
            .help("Share selected documents")
        }
    }

    private func handleDroppedURLs(_ urls: [URL]) -> Bool {
        guard !urls.isEmpty else {
            return false
        }

        coordinator.importDocuments(from: urls)
        return true
    }
}

private struct RootViewImportModifier: ViewModifier {
    let coordinator: LibraryCoordinator
    let allDocuments: [DocumentRecord]

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: Bindable(coordinator).isImporting,
                allowedContentTypes: [.pdf],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    coordinator.importDocuments(from: urls)
                case .failure:
                    coordinator.importSummaryMessage = "The selected files could not be read."
                }
            }
            .alert("Import Summary", isPresented: coordinator.importSummaryBinding) {
                Button("OK", role: .cancel) {
                    coordinator.importSummaryMessage = nil
                }
            } message: {
                Text(coordinator.importSummaryMessage ?? "")
            }
    }
}

private struct RootViewDialogsModifier: ViewModifier {
    let coordinator: LibraryCoordinator
    let allDocuments: [DocumentRecord]

    func body(content: Content) -> some View {
        content
            .confirmationDialog(
                "Remove All From Bin",
                isPresented: Bindable(coordinator).isConfirmingBinRemoval,
                titleVisibility: .visible
            ) {
                Button("Remove All Permanently", role: .destructive) {
                    coordinator.removeAllFromBin()
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("This permanently removes all documents currently in Bin, including stored PDF files. This action cannot be undone.")
            }
            .confirmationDialog(
                coordinator.droppedLabelAssignmentTitle,
                isPresented: coordinator.pendingDroppedLabelAssignmentBinding,
                titleVisibility: .visible
            ) {
                Button("Assign Label", role: .destructive) {
                    coordinator.confirmDroppedLabelAssignment(allDocuments: allDocuments)
                }
                Button("Cancel", role: .cancel) {
                    coordinator.pendingDroppedLabelAssignment = nil
                }
            } message: {
                Text(coordinator.droppedLabelAssignmentMessage)
            }
            .onDeleteCommand {
                coordinator.deleteSelectedDocumentsFromKeyboard()
            }
    }
}

private struct RootViewChangeHandlers: ViewModifier {
    let coordinator: LibraryCoordinator
    let allDocuments: [DocumentRecord]
    let allLabels: [LabelTag]

    /// Lightweight fingerprint that changes when documents are added, removed,
    /// trashed/restored, or have their labels modified -- covering mutations
    /// that `allDocuments.count` alone would miss.
    private var documentFingerprint: Int {
        var hasher = Hasher()
        for document in allDocuments {
            hasher.combine(document.persistentModelID)
            hasher.combine(document.trashedAt)
            hasher.combine(document.labels.count)
        }
        return hasher.finalize()
    }

    private var labelFingerprint: Int {
        var hasher = Hasher()
        for label in allLabels {
            hasher.combine(label.persistentModelID)
            hasher.combine(label.name)
        }
        return hasher.finalize()
    }

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .docNestFocusSearch)) { _ in
                coordinator.searchFocusRequestToken += 1
            }
            .onDisappear {
                coordinator.cancelPendingLabelFilter()
            }
            .onChange(of: coordinator.labelFilterSelection.visualSelection) { _, newSelection in
                coordinator.scheduleLabelFilterApply(immediately: newSelection.isEmpty)
            }
            .onChange(of: coordinator.selectedSection) {
                coordinator.recomputeFilteredDocuments()
                coordinator.pruneSelectedDocumentIDs()
            }
            .onChange(of: coordinator.searchText) {
                coordinator.recomputeFilteredDocuments()
                coordinator.pruneSelectedDocumentIDs()
            }
            .onChange(of: coordinator.selectedDocumentIDs) {
                coordinator.recomputeSelectedDocuments()
            }
            .onChange(of: coordinator.labelFilterSelection.appliedSelection) {
                coordinator.recomputeFilteredDocuments()
                coordinator.pruneSelectedDocumentIDs()
            }
            .onChange(of: documentFingerprint) {
                coordinator.ingest(allDocuments: allDocuments, allLabels: allLabels)
            }
            .onChange(of: labelFingerprint) {
                coordinator.syncLabelFilterSelections(Set(allLabels.map(\.persistentModelID)))
                coordinator.ingest(allDocuments: allDocuments, allLabels: allLabels)
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
