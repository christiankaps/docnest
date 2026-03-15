import OSLog
import SwiftUI
import SwiftData

struct PendingDroppedLabelAssignment {
    let labelID: PersistentIdentifier
    let documentIDs: Set<PersistentIdentifier>
    let alreadyAssignedCount: Int
}

@MainActor
@Observable
final class LibraryCoordinator {
    private static let performanceLogger = Logger(subsystem: "com.kaps.docnest", category: "performance")

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
    var exportSummaryMessage: String?
    var isConfirmingBinRemoval = false
    var pendingDroppedLabelAssignment: PendingDroppedLabelAssignment?
    var labelFilterSelection = DeferredSelectionState<PersistentIdentifier>()

    // MARK: - Cached derived state
    private(set) var allLabels: [LabelTag] = []
    private(set) var activeDocuments: [DocumentRecord] = []
    private(set) var trashedDocuments: [DocumentRecord] = []
    private(set) var filteredDocuments: [DocumentRecord] = []
    private(set) var selectedDocuments: [DocumentRecord] = []
    private(set) var cachedShareURLs: [URL] = []
    private(set) var sidebarCounts = LibrarySidebarCounts.empty

    // MARK: - Internal
    private var pendingLabelFilterApplyTask: Task<Void, Never>?
    private let labelFilterApplyDelay: Duration = .milliseconds(75)
    let recentDocumentLimit = 10

    // MARK: - Data ingestion

    func ingest(allDocuments: [DocumentRecord], allLabels: [LabelTag]) {
        self.allLabels = allLabels

        var active: [DocumentRecord] = []
        var trashed: [DocumentRecord] = []
        for document in allDocuments {
            if document.trashedAt == nil {
                active.append(document)
            } else {
                trashed.append(document)
            }
        }
        activeDocuments = active
        trashedDocuments = trashed

        sidebarCounts = LibrarySidebarCounts(
            activeDocuments: active,
            trashedCount: trashed.count,
            labels: allLabels,
            recentLimit: recentDocumentLimit
        )
        recomputeFilteredDocuments()
        recomputeSelectedDocuments()
    }

    // MARK: - Recomputation

    func recomputeFilteredDocuments() {
        let startTime = Date().timeIntervalSinceReferenceDate

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

        debugLogFilterTiming(
            startTime: startTime,
            sourceCount: sectionDocuments.count,
            filteredCount: filteredDocuments.count,
            queryLength: searchText.count,
            activeLabelFilters: labelFilterSelection.appliedSelection.count
        )
    }

    func recomputeSelectedDocuments() {
        let explicitSelection = filteredDocuments.filter { selectedDocumentIDs.contains($0.persistentModelID) }

        if !explicitSelection.isEmpty {
            selectedDocuments = explicitSelection
        } else {
            if let fallback = filteredDocuments.first {
                selectedDocuments = [fallback]
                selectedDocumentIDs = [fallback.persistentModelID]
            } else {
                selectedDocuments = []
                selectedDocumentIDs = []
            }
        }
        cachedShareURLs = shareableFileURLs(from: selectedDocuments)
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

    func exportDocuments(_ documents: [DocumentRecord]) {
        guard let libraryURL, !documents.isEmpty else { return }
        let result = ExportDocumentsUseCase.exportDocuments(documents, libraryURL: libraryURL)
        if let result, result.hasUserMessage {
            exportSummaryMessage = result.summaryMessage
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

    func assignDroppedLabelToDocuments(_ labelID: UUID, documents: [DocumentRecord]) -> Bool {
        guard let modelContext else { return false }

        let activeDocuments = documents.filter { $0.trashedAt == nil }
        guard !activeDocuments.isEmpty else { return false }

        guard let label = allLabels.first(where: { $0.id == labelID }) else {
            return false
        }

        do {
            try ManageLabelsUseCase.assign(label, to: activeDocuments, using: modelContext)
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

        // Fast path: assigning one file should be immediate and not require confirmation.
        if candidateDocuments.count == 1, let document = candidateDocuments.first, let modelContext {
            let alreadyAssigned = document.labels.contains { $0.persistentModelID == label.persistentModelID }

            if alreadyAssigned {
                return true
            }

            do {
                try ManageLabelsUseCase.assign(label, to: document, using: modelContext)
                return true
            } catch {
                importSummaryMessage = error.localizedDescription
                return false
            }
        }

        let alreadyAssignedCount = candidateDocuments.reduce(into: 0) { count, document in
            if document.labels.contains(where: { $0.persistentModelID == label.persistentModelID }) {
                count += 1
            }
        }

        pendingDroppedLabelAssignment = PendingDroppedLabelAssignment(
            labelID: label.persistentModelID,
            documentIDs: Set(candidateDocuments.map(\.persistentModelID)),
            alreadyAssignedCount: alreadyAssignedCount
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

        let missingAssignments = documentsToAssign.filter { document in
            !document.labels.contains(where: { $0.persistentModelID == label.persistentModelID })
        }

        guard !missingAssignments.isEmpty else {
            pendingDroppedLabelAssignment = nil
            return
        }

        do {
            try ManageLabelsUseCase.assign(label, to: missingAssignments, using: modelContext)
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

        Task { @MainActor in
            let importResult = await ImportPDFDocumentsUseCase.execute(
                urls: urls,
                into: libraryURL,
                autoAssignLabels: activeFilterLabels,
                using: modelContext
            )

            if importResult.hasUserMessage {
                importSummaryMessage = importResult.summaryMessage
            }
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

    var exportSummaryBinding: Binding<Bool> {
        Binding(
            get: { self.exportSummaryMessage != nil },
            set: { newValue in
                if !newValue {
                    self.exportSummaryMessage = nil
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

        let total = pending.documentIDs.count
        let alreadyAssigned = pending.alreadyAssignedCount
        let newlyAssigned = max(total - alreadyAssigned, 0)

        if alreadyAssigned == 0 {
            return "Assign this label to \(total) documents?"
        }

        return "Assign this label to \(total) documents? \(newlyAssigned) will be updated and \(alreadyAssigned) already have this label."
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

    private func debugLogFilterTiming(
        startTime: TimeInterval,
        sourceCount: Int,
        filteredCount: Int,
        queryLength: Int,
        activeLabelFilters: Int
    ) {
        #if DEBUG
        let elapsedMs = (Date().timeIntervalSinceReferenceDate - startTime) * 1000
        Self.performanceLogger.log(
            "[Performance][Filter] section=\(self.selectedSection.rawValue, privacy: .public) source=\(sourceCount) filtered=\(filteredCount) query=\(queryLength) labels=\(activeLabelFilters) duration=\(elapsedMs, format: .fixed(precision: 2))ms"
        )
        #endif
    }
}

extension LibrarySidebarCounts {
    static let empty = LibrarySidebarCounts(activeDocuments: [], trashedCount: 0, labels: [], recentLimit: 10)
}
