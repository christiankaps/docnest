import SwiftUI
import SwiftData

struct PendingDroppedLabelAssignment {
    let labelID: PersistentIdentifier
    let documentIDs: Set<PersistentIdentifier>
}

@MainActor
@Observable
final class LibraryCoordinator {
    // MARK: - Injected dependencies (set once by RootView)
    var libraryURL: URL?
    var modelContext: ModelContext?

    // MARK: - UI state (moved from RootView @State)
    var selectedSection: LibrarySection = .allDocuments
    var selectedDocumentIDs: Set<PersistentIdentifier> = []
    var searchText = ""
    var searchFocusRequestToken = 0
    var isImporting = false
    var isDropTargeted = false
    var documentListViewMode: DocumentListViewMode = .list
    var importSummaryMessage: String?
    var isConfirmingBinRemoval = false
    var pendingDroppedLabelAssignment: PendingDroppedLabelAssignment?
    var labelFilterSelection = DeferredSelectionState<PersistentIdentifier>()

    // MARK: - Cached derived state
    private(set) var allLabels: [LabelTag] = []
    private(set) var activeDocuments: [DocumentRecord] = []
    private(set) var trashedDocuments: [DocumentRecord] = []
    private(set) var filteredDocuments: [DocumentRecord] = []
    private(set) var selectedDocuments: [DocumentRecord] = []
    private(set) var sidebarCounts = LibrarySidebarCounts.empty

    // MARK: - Internal
    private var pendingLabelFilterApplyTask: Task<Void, Never>?
    private let labelFilterApplyDelay: Duration = .milliseconds(75)
    let recentDocumentLimit = 10

    // MARK: - Data ingestion

    func ingest(allDocuments: [DocumentRecord], allLabels: [LabelTag]) {
        self.allLabels = allLabels
        activeDocuments = allDocuments.filter { $0.trashedAt == nil }
        trashedDocuments = allDocuments.filter { $0.trashedAt != nil }
        sidebarCounts = LibrarySidebarCounts(
            documents: allDocuments,
            labels: allLabels,
            recentLimit: recentDocumentLimit
        )
        recomputeFilteredDocuments()
        recomputeSelectedDocuments()
    }

    // MARK: - Recomputation

    func recomputeFilteredDocuments() {
        let sectionDocuments: [DocumentRecord] = switch selectedSection {
        case .allDocuments:
            activeDocuments
        case .recent:
            Array(activeDocuments.prefix(recentDocumentLimit))
        case .needsLabels:
            activeDocuments.filter { $0.labels.isEmpty }
        case .bin:
            trashedDocuments
        }

        filteredDocuments = SearchDocumentsUseCase.filter(
            sectionDocuments,
            query: searchText,
            selectedLabelIDs: labelFilterSelection.appliedSelection
        )
    }

    func recomputeSelectedDocuments() {
        let explicitSelection = filteredDocuments.filter { selectedDocumentIDs.contains($0.persistentModelID) }

        if !explicitSelection.isEmpty {
            selectedDocuments = explicitSelection
        } else {
            selectedDocuments = filteredDocuments.first.map { [$0] } ?? []
        }
    }

    func pruneSelectedDocumentIDs() {
        let validIDs = Set(filteredDocuments.map(\.persistentModelID))
        selectedDocumentIDs.formIntersection(validIDs)
        recomputeSelectedDocuments()
    }

    // MARK: - Label filter scheduling

    func scheduleLabelFilterApply(immediately: Bool) {
        pendingLabelFilterApplyTask?.cancel()

        guard !immediately else {
            labelFilterSelection.commitVisualSelection()
            recomputeFilteredDocuments()
            pruneSelectedDocumentIDs()
            return
        }

        pendingLabelFilterApplyTask = Task { @MainActor in
            try? await Task.sleep(for: labelFilterApplyDelay)

            guard !Task.isCancelled else {
                return
            }

            labelFilterSelection.commitVisualSelection()
            recomputeFilteredDocuments()
            pruneSelectedDocumentIDs()
        }
    }

    func cancelPendingLabelFilter() {
        pendingLabelFilterApplyTask?.cancel()
    }

    func syncLabelFilterSelections(_ availableIDs: Set<PersistentIdentifier>) {
        pendingLabelFilterApplyTask?.cancel()
        labelFilterSelection.syncAvailableSelections(availableIDs)
    }

    // MARK: - Actions

    func restoreDocumentFromBin(_ document: DocumentRecord) {
        guard let modelContext else { return }
        do {
            try DeleteDocumentsUseCase.restoreFromBin([document], using: modelContext)
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    func restoreAllFromBin() {
        guard let modelContext else { return }
        do {
            try DeleteDocumentsUseCase.restoreFromBin(trashedDocuments, using: modelContext)
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    func removeAllFromBin() {
        guard let modelContext, let libraryURL else { return }
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

    func moveToBin(_ documents: [DocumentRecord]) {
        guard let modelContext else { return }
        do {
            try DeleteDocumentsUseCase.moveToBin(documents, using: modelContext)
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    func toggleLabel(_ label: LabelTag, on documents: [DocumentRecord]) {
        guard let modelContext else { return }
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

    func assignDroppedLabelToDocument(_ labelID: UUID, document: DocumentRecord) -> Bool {
        guard let modelContext else { return false }
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

    func handleDroppedDocumentIDs(_ droppedIDs: [String]) -> Bool {
        guard let modelContext else { return false }
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

    func handleDroppedDocumentsOnLabel(_ payloadItems: [String], label: LabelTag) -> Bool {
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

    func confirmDroppedLabelAssignment(allDocuments: [DocumentRecord]) {
        guard let modelContext,
              let pending = pendingDroppedLabelAssignment,
              let label = allLabels.first(where: { $0.persistentModelID == pending.labelID }) else {
            pendingDroppedLabelAssignment = nil
            return
        }

        let documentsToAssign = allDocuments.filter { pending.documentIDs.contains($0.persistentModelID) }
        guard !documentsToAssign.isEmpty else {
            pendingDroppedLabelAssignment = nil
            return
        }

        do {
            try ManageLabelsUseCase.assign(label, to: documentsToAssign, using: modelContext)
            pendingDroppedLabelAssignment = nil
        } catch {
            pendingDroppedLabelAssignment = nil
            importSummaryMessage = error.localizedDescription
        }
    }

    func deleteSelectedDocumentsFromKeyboard() {
        guard let modelContext else { return }
        let explicitSelection = filteredDocuments.filter { selectedDocumentIDs.contains($0.persistentModelID) }
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

    func importDocuments(from urls: [URL]) {
        guard let modelContext, let libraryURL, !urls.isEmpty else {
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

    func shareableFileURLs(from documents: [DocumentRecord]) -> [URL] {
        guard let libraryURL else { return [] }
        return documents.compactMap { document in
            guard let path = document.storedFilePath,
                  DocumentStorageService.fileExists(at: path, libraryURL: libraryURL) else {
                return nil
            }
            return DocumentStorageService.fileURL(for: path, libraryURL: libraryURL)
        }
    }

    // MARK: - Binding helpers

    var visualSelectedLabelIDsBinding: Binding<Set<PersistentIdentifier>> {
        Binding(
            get: { self.labelFilterSelection.visualSelection },
            set: { newSelection in
                self.labelFilterSelection.replaceVisualSelection(with: newSelection)
            }
        )
    }

    var importSummaryBinding: Binding<Bool> {
        Binding(
            get: { self.importSummaryMessage != nil },
            set: { newValue in
                if !newValue {
                    self.importSummaryMessage = nil
                }
            }
        )
    }

    var pendingDroppedLabelAssignmentBinding: Binding<Bool> {
        Binding(
            get: { self.pendingDroppedLabelAssignment != nil },
            set: { newValue in
                if !newValue {
                    self.pendingDroppedLabelAssignment = nil
                }
            }
        )
    }

    var droppedLabelAssignmentTitle: String {
        guard let pending = pendingDroppedLabelAssignment,
              let label = allLabels.first(where: { $0.persistentModelID == pending.labelID }) else {
            return "Assign Label"
        }

        return "Assign \"\(label.name)\""
    }

    var droppedLabelAssignmentMessage: String {
        guard let pending = pendingDroppedLabelAssignment else {
            return ""
        }

        if pending.documentIDs.count == 1 {
            return "Assign this label to 1 document?"
        }

        return "Assign this label to \(pending.documentIDs.count) documents?"
    }

    // MARK: - Private helpers

    func parseDroppedDocumentIDs(_ payloadItems: [String]) -> Set<UUID> {
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
}

extension LibrarySidebarCounts {
    static let empty = LibrarySidebarCounts(documents: [], labels: [], recentLimit: 10)
}
