import SwiftUI
import SwiftData

struct RootView: View {
    let libraryURL: URL
    private let labelFilterApplyDelay: Duration = .milliseconds(75)
    private let recentDocumentLimit = 10

    @State private var columnVisibility: NavigationSplitViewVisibility = .all
    @State private var selectedSection: LibrarySection = .allDocuments
    @State private var labelFilterSelection = DeferredSelectionState<PersistentIdentifier>()
    @State private var selectedDocumentIDs: Set<PersistentIdentifier> = []
    @State private var searchText = ""
    @State private var searchFocusRequestToken = 0
    @State private var isImporting = false
    @State private var isDropTargeted = false
    @State private var documentListViewMode: DocumentListViewMode = .list
    @State private var importSummaryMessage: String?
    @State private var pendingLabelFilterApplyTask: Task<Void, Never>?
    @State private var isConfirmingBinRemoval = false
    @State private var pendingDroppedLabelAssignment: PendingDroppedLabelAssignment?
    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DocumentRecord.importedAt, order: .reverse)
    private var allDocuments: [DocumentRecord]

    @Query(sort: [SortDescriptor(\LabelTag.sortOrder, order: .forward), SortDescriptor(\LabelTag.name, order: .forward)])
    private var allLabels: [LabelTag]

    private var activeDocuments: [DocumentRecord] {
        allDocuments.filter { $0.trashedAt == nil }
    }

    private var trashedDocuments: [DocumentRecord] {
        allDocuments.filter { $0.trashedAt != nil }
    }

    private func computeFilteredDocuments(active: [DocumentRecord], trashed: [DocumentRecord]) -> [DocumentRecord] {
        let sectionDocuments: [DocumentRecord] = switch selectedSection {
        case .allDocuments:
            active
        case .recent:
            Array(active.prefix(recentDocumentLimit))
        case .needsLabels:
            active.filter { $0.labels.isEmpty }
        case .bin:
            trashed
        }

        return SearchDocumentsUseCase.filter(
            sectionDocuments,
            query: searchText,
            selectedLabelIDs: labelFilterSelection.appliedSelection
        )
    }

    private func computeSelectedDocuments(from filtered: [DocumentRecord]) -> [DocumentRecord] {
        let explicitSelection = filtered.filter { selectedDocumentIDs.contains($0.persistentModelID) }

        if !explicitSelection.isEmpty {
            return explicitSelection
        }

        return filtered.first.map { [$0] } ?? []
    }

    var body: some View {
        let active = activeDocuments
        let trashed = trashedDocuments
        let hasTrashed = !trashed.isEmpty
        let counts = LibrarySidebarCounts(documents: allDocuments, labels: allLabels, recentLimit: recentDocumentLimit)
        let filtered = computeFilteredDocuments(active: active, trashed: trashed)
        let selected = computeSelectedDocuments(from: filtered)

        NavigationSplitView(columnVisibility: $columnVisibility) {
            LibrarySidebarView(
                selectedSection: $selectedSection,
                labels: allLabels,
                counts: counts,
                canRestoreAllFromBin: hasTrashed,
                canRemoveAllFromBin: hasTrashed,
                onRestoreAllFromBin: restoreAllFromBin,
                onRemoveAllFromBin: { isConfirmingBinRemoval = true },
                onDropDocumentsToBin: handleDroppedDocumentIDs,
                onDropDocumentsToLabel: handleDroppedDocumentsOnLabel,
                selectedLabelIDs: visualSelectedLabelIDsBinding
            )
            .navigationSplitViewColumnWidth(
                min: AppSplitViewLayout.sidebarWidth,
                ideal: AppSplitViewLayout.sidebarWidth,
                max: AppSplitViewLayout.sidebarWidth
            )
        } content: {
            ZStack {
                DocumentListView(
                    documents: filtered,
                    selectedSection: selectedSection,
                    libraryURL: libraryURL,
                    allLabels: allLabels,
                    onRestoreDocument: restoreDocumentFromBin,
                    onMoveToBin: moveToBinFromContextMenu,
                    onToggleLabel: toggleLabelFromContextMenu,
                    onAssignDroppedLabelToDocument: assignDroppedLabelToDocument,
                    selectedDocumentIDs: $selectedDocumentIDs,
                    viewMode: $documentListViewMode
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
            .navigationSplitViewColumnWidth(
                min: AppSplitViewLayout.documentListMinWidth,
                ideal: AppSplitViewLayout.documentListIdealWidth
            )
        } detail: {
            DocumentInspectorView(
                documents: selected,
                libraryURL: libraryURL
            )
            .navigationSplitViewColumnWidth(
                min: AppSplitViewLayout.inspectorWidth,
                ideal: AppSplitViewLayout.inspectorWidth,
                max: AppSplitViewLayout.inspectorWidth
            )
        }
        .navigationSplitViewStyle(.balanced)
        .onAppear {
            columnVisibility = .all
        }
        .toolbar {
            ToolbarItem(placement: .principal) {
                SearchToolbarField(
                    text: $searchText,
                    focusRequestToken: searchFocusRequestToken
                )
                .frame(width: 280)
            }

            ToolbarItem(placement: .primaryAction) {
                Button {
                    isImporting = true
                } label: {
                    Label("Import", systemImage: "plus")
                }
            }

            ToolbarItem(placement: .primaryAction) {
                let shareURLs = shareableFileURLs(from: selected)
                ShareLink(items: shareURLs) {
                    Label("Share", systemImage: "square.and.arrow.up")
                }
                .disabled(shareURLs.isEmpty)
                .help("Share selected documents")
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
        .onChange(of: labelFilterSelection.visualSelection) { _, newSelection in
            scheduleLabelFilterApply(immediately: newSelection.isEmpty)
        }
        .onChange(of: allLabels.count) {
            pendingLabelFilterApplyTask?.cancel()
            labelFilterSelection.syncAvailableSelections(Set(allLabels.map(\.persistentModelID)))
        }
        .onChange(of: selectedSection) {
            pruneSelectedDocumentIDs()
        }
        .onChange(of: searchText) {
            pruneSelectedDocumentIDs()
        }
        .onChange(of: labelFilterSelection.appliedSelection) {
            pruneSelectedDocumentIDs()
        }
        .onChange(of: allDocuments.count) {
            pruneSelectedDocumentIDs()
        }
        .onReceive(NotificationCenter.default.publisher(for: .docNestFocusSearch)) { _ in
            searchFocusRequestToken += 1
        }
        .onDisappear {
            pendingLabelFilterApplyTask?.cancel()
        }
        .onDeleteCommand {
            deleteSelectedDocumentsFromKeyboard()
        }
        .confirmationDialog(
            "Remove All From Bin",
            isPresented: $isConfirmingBinRemoval,
            titleVisibility: .visible
        ) {
            Button("Remove All Permanently", role: .destructive) {
                removeAllFromBin()
            }

            Button("Cancel", role: .cancel) {}
        } message: {
            Text("This permanently removes all documents currently in Bin, including stored PDF files. This action cannot be undone.")
        }
        .confirmationDialog(
            droppedLabelAssignmentTitle,
            isPresented: pendingDroppedLabelAssignmentBinding,
            titleVisibility: .visible
        ) {
            Button("Assign Label", role: .destructive) {
                confirmDroppedLabelAssignment()
            }

            Button("Cancel", role: .cancel) {
                pendingDroppedLabelAssignment = nil
            }
        } message: {
            Text(droppedLabelAssignmentMessage)
        }
    }

    private var visualSelectedLabelIDsBinding: Binding<Set<PersistentIdentifier>> {
        Binding(
            get: { labelFilterSelection.visualSelection },
            set: { newSelection in
                labelFilterSelection.replaceVisualSelection(with: newSelection)
            }
        )
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

    private var pendingDroppedLabelAssignmentBinding: Binding<Bool> {
        Binding(
            get: { pendingDroppedLabelAssignment != nil },
            set: { newValue in
                if !newValue {
                    pendingDroppedLabelAssignment = nil
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

        let activeFilterLabels = allLabels.filter { label in
            labelFilterSelection.visualSelection.contains(label.persistentModelID)
        }

        let importResult = ImportPDFDocumentsUseCase.execute(
            urls: urls,
            into: libraryURL,
            autoAssignLabels: activeFilterLabels,
            using: modelContext
        )

        if importResult.hasUserMessage {
            importSummaryMessage = importResult.summaryMessage
        }
    }

    private func scheduleLabelFilterApply(immediately: Bool) {
        pendingLabelFilterApplyTask?.cancel()

        guard !immediately else {
            labelFilterSelection.commitVisualSelection()
            return
        }

        pendingLabelFilterApplyTask = Task { @MainActor in
            try? await Task.sleep(for: labelFilterApplyDelay)

            guard !Task.isCancelled else {
                return
            }

            labelFilterSelection.commitVisualSelection()
        }
    }

    private func restoreDocumentFromBin(_ document: DocumentRecord) {
        do {
            try DeleteDocumentsUseCase.restoreFromBin([document], using: modelContext)
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    private func restoreAllFromBin() {
        do {
            try DeleteDocumentsUseCase.restoreFromBin(trashedDocuments, using: modelContext)
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    private func removeAllFromBin() {
        do {
            try DeleteDocumentsUseCase.execute(
                trashedDocuments,
                mode: .deleteStoredFiles,
                libraryURL: libraryURL,
                using: modelContext
            )
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    private func handleDroppedDocumentIDs(_ droppedIDs: [String]) -> Bool {
        let uuidSet = parseDroppedDocumentIDs(droppedIDs)
        guard !uuidSet.isEmpty else {
            return false
        }

        let documentsToMove = activeDocuments.filter { uuidSet.contains($0.id) }
        guard !documentsToMove.isEmpty else {
            return false
        }

        do {
            try DeleteDocumentsUseCase.moveToBin(documentsToMove, using: modelContext)
            return true
        } catch {
            importSummaryMessage = error.localizedDescription
            return false
        }
    }

    private func handleDroppedDocumentsOnLabel(_ payloadItems: [String], label: LabelTag) -> Bool {
        let documentIDs = parseDroppedDocumentIDs(payloadItems)
        guard !documentIDs.isEmpty else {
            return false
        }

        let candidateDocuments = activeDocuments.filter { documentIDs.contains($0.id) }
        guard !candidateDocuments.isEmpty else {
            return false
        }

        pendingDroppedLabelAssignment = PendingDroppedLabelAssignment(
            labelID: label.persistentModelID,
            documentIDs: Set(candidateDocuments.map(\.persistentModelID))
        )
        return true
    }

    private func confirmDroppedLabelAssignment() {
        guard let pendingDroppedLabelAssignment,
              let label = allLabels.first(where: { $0.persistentModelID == pendingDroppedLabelAssignment.labelID }) else {
            self.pendingDroppedLabelAssignment = nil
            return
        }

        let documentsToAssign = allDocuments.filter { pendingDroppedLabelAssignment.documentIDs.contains($0.persistentModelID) }
        guard !documentsToAssign.isEmpty else {
            self.pendingDroppedLabelAssignment = nil
            return
        }

        do {
            try ManageLabelsUseCase.assign(label, to: documentsToAssign, using: modelContext)
            self.pendingDroppedLabelAssignment = nil
        } catch {
            self.pendingDroppedLabelAssignment = nil
            importSummaryMessage = error.localizedDescription
        }
    }

    private func pruneSelectedDocumentIDs() {
        let active = activeDocuments
        let trashed = trashedDocuments
        let filtered = computeFilteredDocuments(active: active, trashed: trashed)
        let validIDs = Set(filtered.map(\.persistentModelID))
        selectedDocumentIDs.formIntersection(validIDs)
    }

    private func deleteSelectedDocumentsFromKeyboard() {
        let active = activeDocuments
        let trashed = trashedDocuments
        let filtered = computeFilteredDocuments(active: active, trashed: trashed)
        let explicitSelection = filtered.filter { selectedDocumentIDs.contains($0.persistentModelID) }
        guard !explicitSelection.isEmpty else {
            return
        }

        do {
            if selectedSection == .bin {
                let mode: DocumentDeletionMode = libraryURL == nil ? .removeFromLibrary : .deleteStoredFiles
                try DeleteDocumentsUseCase.execute(
                    explicitSelection,
                    mode: mode,
                    libraryURL: libraryURL,
                    using: modelContext
                )
            } else {
                try DeleteDocumentsUseCase.moveToBin(explicitSelection, using: modelContext)
            }
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    private func assignDroppedLabelToDocument(_ labelID: UUID, document: DocumentRecord) -> Bool {
        guard document.trashedAt == nil else {
            return false
        }

        guard let label = allLabels.first(where: { $0.id == labelID }) else {
            return false
        }

        do {
            try ManageLabelsUseCase.assign(label, to: document, using: modelContext)
            return true
        } catch {
            importSummaryMessage = error.localizedDescription
            return false
        }
    }

    private var droppedLabelAssignmentTitle: String {
        guard let pendingDroppedLabelAssignment,
              let label = allLabels.first(where: { $0.persistentModelID == pendingDroppedLabelAssignment.labelID }) else {
            return "Assign Label"
        }

        return "Assign \"\(label.name)\""
    }

    private var droppedLabelAssignmentMessage: String {
        guard let pendingDroppedLabelAssignment else {
            return ""
        }

        if pendingDroppedLabelAssignment.documentIDs.count == 1 {
            return "Assign this label to 1 document?"
        }

        return "Assign this label to \(pendingDroppedLabelAssignment.documentIDs.count) documents?"
    }

    private func moveToBinFromContextMenu(_ documents: [DocumentRecord]) {
        do {
            try DeleteDocumentsUseCase.moveToBin(documents, using: modelContext)
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    private func toggleLabelFromContextMenu(_ label: LabelTag, _ documents: [DocumentRecord]) {
        do {
            if documents.allSatisfy({ doc in
                doc.labels.contains(where: { $0.persistentModelID == label.persistentModelID })
            }) {
                try ManageLabelsUseCase.remove(label, from: documents, using: modelContext)
            } else {
                try ManageLabelsUseCase.assign(label, to: documents, using: modelContext)
            }
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    private func shareableFileURLs(from documents: [DocumentRecord]) -> [URL] {
        documents.compactMap { document in
            guard let path = document.storedFilePath,
                  DocumentStorageService.fileExists(at: path, libraryURL: libraryURL) else {
                return nil
            }
            return DocumentStorageService.fileURL(for: path, libraryURL: libraryURL)
        }
    }

    private func parseDroppedDocumentIDs(_ payloadItems: [String]) -> Set<UUID> {
        var documentIDs = Set<UUID>()

        for payload in payloadItems {
            if let extractedIDs = DocumentFileDragPayload.documentIDs(from: payload) {
                documentIDs.formUnion(extractedIDs)
                continue
            }

            if let singleID = UUID(uuidString: payload) {
                documentIDs.insert(singleID)
            }
        }

        return documentIDs
    }

    private struct PendingDroppedLabelAssignment {
        let labelID: PersistentIdentifier
        let documentIDs: Set<PersistentIdentifier>
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