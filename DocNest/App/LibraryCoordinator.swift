import OSLog
import SwiftUI
import SwiftData

enum SidebarSelection: Hashable {
    case section(LibrarySection)
    case smartFolder(PersistentIdentifier)
}

struct ImportProgress {
    let total: Int
    let completed: Int
}

struct OCRProgress {
    let total: Int
    let completed: Int
    let currentTitle: String
}

struct PendingDroppedLabelAssignment {
    let labelID: PersistentIdentifier
    let documentIDs: Set<PersistentIdentifier>
    let alreadyAssignedCount: Int
}

enum WatchFolderStatus {
    case monitoring
    case paused
    case pathInvalid
}

@MainActor
@Observable
final class LibraryCoordinator {
    private static let performanceLogger = Logger(subsystem: "com.kaps.docnest", category: "performance")

    // MARK: - Injected dependencies (set once by RootView)
    var libraryURL: URL?
    var modelContext: ModelContext?

    // MARK: - UI state (moved from RootView @State)
    var sidebarSelection: SidebarSelection = .section(.allDocuments)
    var selectedDocumentIDs: Set<PersistentIdentifier> = []
    var searchText = ""
    var searchFocusRequestToken = 0
    var isImporting = false
    var isDropTargeted = false
    private(set) var importProgress: ImportProgress?
    var documentListViewMode: DocumentListViewMode = .list
    var importSummaryMessage: String?
    var exportSummaryMessage: String?
    var isConfirmingBinRemoval = false
    var pendingDroppedLabelAssignment: PendingDroppedLabelAssignment?
    var isQuickLabelPickerPresented = false
    var isLabelManagerPresented = false
    var isWatchFolderSettingsPresented = false
    var labelFilterSelection = DeferredSelectionState<PersistentIdentifier>()

    // MARK: - OCR state
    private(set) var ocrProgress: OCRProgress?
    private var activeOCRTask: Task<Void, Never>?

    // MARK: - Cached derived state
    private(set) var allLabels: [LabelTag] = []
    private(set) var allLabelGroups: [LabelGroup] = []
    private(set) var allSmartFolders: [SmartFolder] = []
    private(set) var smartFolderCounts: [PersistentIdentifier: Int] = [:]
    private(set) var allWatchFolders: [WatchFolder] = []
    private(set) var watchFolderStatuses: [UUID: WatchFolderStatus] = [:]
    private(set) var activeDocuments: [DocumentRecord] = []
    private(set) var trashedDocuments: [DocumentRecord] = []
    private(set) var filteredDocuments: [DocumentRecord] = []
    private(set) var selectedDocuments: [DocumentRecord] = []
    private(set) var cachedShareURLs: [URL] = []
    private(set) var sidebarCounts = LibrarySidebarCounts.empty

    // MARK: - Internal
    private var activeImportTask: Task<Void, Never>?
    private let folderMonitorService = FolderMonitorService()
    private var pendingLabelFilterApplyTask: Task<Void, Never>?
    private let labelFilterApplyDelay: Duration = .milliseconds(75)
    let recentDocumentLimit = 10

    // MARK: - Convenience selection helpers

    var selectedSection: LibrarySection? {
        if case .section(let s) = sidebarSelection { return s }
        return nil
    }

    var selectedSmartFolderID: PersistentIdentifier? {
        if case .smartFolder(let id) = sidebarSelection { return id }
        return nil
    }

    var isBinSelected: Bool {
        sidebarSelection == .section(.bin)
    }

    /// Whether the current interactive label filter selection exactly matches a smart folder's labels.
    func labelFilterMatchesSmartFolder(_ folder: SmartFolder) -> Bool {
        guard selectedSmartFolderID == nil else { return false }
        let appliedIDs = labelFilterSelection.visualSelection
        guard !appliedIDs.isEmpty else { return false }
        let folderLabelPIDs = resolvedLabelPersistentIDs(from: folder.labelIDs)
        return appliedIDs == folderLabelPIDs
    }

    /// The set of label PersistentIdentifiers that should appear highlighted in the sidebar.
    /// When a smart folder is selected, this reflects the folder's labels instead of the interactive filter.
    var effectiveHighlightedLabelIDs: Set<PersistentIdentifier> {
        if let folderID = selectedSmartFolderID,
           let folder = allSmartFolders.first(where: { $0.persistentModelID == folderID }) {
            return resolvedLabelPersistentIDs(from: folder.labelIDs)
        }
        return labelFilterSelection.visualSelection
    }

    // MARK: - Data ingestion

    func ingest(allDocuments: [DocumentRecord], allLabels: [LabelTag], allSmartFolders: [SmartFolder] = [], allLabelGroups: [LabelGroup] = [], allWatchFolders: [WatchFolder] = []) {
        self.allLabels = allLabels
        self.allSmartFolders = allSmartFolders
        self.allLabelGroups = allLabelGroups
        self.allWatchFolders = allWatchFolders

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

        recomputeSmartFolderCounts()
        recomputeFilteredDocuments()
        recomputeSelectedDocuments()
    }

    // MARK: - Recomputation

    func recomputeFilteredDocuments() {
        #if DEBUG
        let startTime = Date().timeIntervalSinceReferenceDate
        #endif

        let sectionDocuments = sectionScopedDocuments

        if selectedSmartFolderID != nil {
            // Smart folder already applied its own query + label filter
            filteredDocuments = sectionDocuments
        } else {
            filteredDocuments = SearchDocumentsUseCase.filter(
                sectionDocuments,
                query: searchText,
                selectedLabelIDs: labelFilterSelection.appliedSelection
            )
        }

        recomputeSidebarCounts(sectionDocuments: sectionDocuments)

        #if DEBUG
        debugLogFilterTiming(
            startTime: startTime,
            sourceCount: sectionDocuments.count,
            filteredCount: filteredDocuments.count,
            queryLength: searchText.count,
            activeLabelFilters: labelFilterSelection.appliedSelection.count
        )
        #endif
    }

    private var sectionScopedDocuments: [DocumentRecord] {
        switch sidebarSelection {
        case .section(.allDocuments):
            activeDocuments
        case .section(.recent):
            Array(activeDocuments.prefix(recentDocumentLimit))
        case .section(.needsLabels):
            activeDocuments.filter { $0.labels.isEmpty }
        case .section(.bin):
            trashedDocuments
        case .smartFolder(let folderID):
            smartFolderDocuments(for: folderID)
        }
    }

    private func smartFolderDocuments(for folderID: PersistentIdentifier) -> [DocumentRecord] {
        guard let folder = allSmartFolders.first(where: { $0.persistentModelID == folderID }) else {
            return []
        }
        let labelPIDs = resolvedLabelPersistentIDs(from: folder.labelIDs)
        return SearchDocumentsUseCase.filter(
            activeDocuments,
            query: "",
            selectedLabelIDs: labelPIDs
        )
    }

    private func resolvedLabelPersistentIDs(from uuids: [UUID]) -> Set<PersistentIdentifier> {
        var result = Set<PersistentIdentifier>()
        for uuid in uuids {
            if let label = allLabels.first(where: { $0.id == uuid }) {
                result.insert(label.persistentModelID)
            }
        }
        return result
    }

    private func recomputeSmartFolderCounts() {
        var counts: [PersistentIdentifier: Int] = [:]
        for folder in allSmartFolders {
            let labelPIDs = resolvedLabelPersistentIDs(from: folder.labelIDs)
            counts[folder.persistentModelID] = SearchDocumentsUseCase.filter(
                activeDocuments,
                query: "",
                selectedLabelIDs: labelPIDs
            ).count
        }
        smartFolderCounts = counts
    }

    private func recomputeSidebarCounts(sectionDocuments: [DocumentRecord]) {
        sidebarCounts = LibrarySidebarCounts(
            activeDocuments: activeDocuments,
            trashedCount: trashedDocuments.count,
            labels: allLabels,
            recentLimit: recentDocumentLimit,
            labelSourceDocuments: sectionDocuments,
            activeLabelFilterIDs: labelFilterSelection.appliedSelection
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
            if isBinSelected {
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

        let activeFilterLabels: [LabelTag]
        if let folderID = selectedSmartFolderID,
           let folder = allSmartFolders.first(where: { $0.persistentModelID == folderID }) {
            let folderLabelUUIDs = Set(folder.labelIDs)
            activeFilterLabels = allLabels.filter { folderLabelUUIDs.contains($0.id) }
        } else {
            activeFilterLabels = allLabels.filter { label in
                labelFilterSelection.visualSelection.contains(label.persistentModelID)
            }
        }

        importProgress = ImportProgress(total: 0, completed: 0)

        activeImportTask = Task { @MainActor [weak self] in
            let importResult = await ImportPDFDocumentsUseCase.execute(
                urls: urls,
                into: libraryURL,
                autoAssignLabels: activeFilterLabels,
                using: modelContext
            ) { [weak self] completed, total in
                self?.importProgress = ImportProgress(total: total, completed: completed)
            }

            self?.importProgress = nil
            self?.activeImportTask = nil

            if importResult.hasUserMessage {
                self?.importSummaryMessage = importResult.summaryMessage
            }
        }
    }

    func cancelImport() {
        activeImportTask?.cancel()
        activeImportTask = nil
        importProgress = nil
    }

    // MARK: - OCR actions

    func runOCRBackfill(documents: [DocumentRecord], libraryURL: URL, modelContext: ModelContext) {
        guard activeOCRTask == nil else { return }

        activeOCRTask = Task { @MainActor [weak self] in
            await ExtractDocumentTextUseCase.backfillAll(
                documents: documents,
                libraryURL: libraryURL,
                modelContext: modelContext
            ) { [weak self] completed, total, title in
                self?.ocrProgress = OCRProgress(total: total, completed: completed, currentTitle: title)
            }

            self?.ocrProgress = nil
            self?.activeOCRTask = nil
        }
    }

    func reExtractText(for documents: [DocumentRecord], libraryURL: URL, modelContext: ModelContext) {
        guard !documents.isEmpty else { return }

        // Mark documents for re-extraction by clearing their text and ocrCompleted flag
        for document in documents {
            document.fullText = nil
            document.ocrCompleted = false
        }
        try? modelContext.save()

        // If an OCR task is already running, the backfill will pick these up.
        // Otherwise, start a new backfill.
        if activeOCRTask == nil {
            runOCRBackfill(documents: documents, libraryURL: libraryURL, modelContext: modelContext)
        }
    }

    func reExtractDocumentDate(for documents: [DocumentRecord], modelContext: ModelContext) {
        guard !documents.isEmpty else { return }
        for document in documents {
            if let text = document.fullText, !text.isEmpty,
               let extracted = DocumentDateExtractor.extractDate(from: text) {
                document.documentDate = extracted
            } else {
                document.documentDate = document.importedAt
            }
        }
        try? modelContext.save()
    }

    func cancelOCR() {
        activeOCRTask?.cancel()
        activeOCRTask = nil
        ocrProgress = nil
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

    // MARK: - Smart folder helpers

    func assignSmartFolderLabels(_ folder: SmartFolder, toDroppedPayload items: [String]) -> Bool {
        guard let modelContext else { return false }

        let documentIDs = parseDroppedDocumentIDs(items)
        guard !documentIDs.isEmpty else { return false }

        let documents = activeDocuments.filter { documentIDs.contains($0.id) }
        guard !documents.isEmpty else { return false }

        let folderLabelUUIDs = Set(folder.labelIDs)
        let labels = allLabels.filter { folderLabelUUIDs.contains($0.id) }
        guard !labels.isEmpty else { return false }

        do {
            for label in labels {
                let needsAssignment = documents.filter { doc in
                    !doc.labels.contains(where: { $0.persistentModelID == label.persistentModelID })
                }
                if !needsAssignment.isEmpty {
                    try ManageLabelsUseCase.assign(label, to: needsAssignment, using: modelContext)
                }
            }
            return true
        } catch {
            importSummaryMessage = error.localizedDescription
            return false
        }
    }

    func prefillLabelIDsForNewSmartFolder() -> [UUID] {
        labelFilterSelection.appliedSelection.compactMap { persistentID in
            allLabels.first(where: { $0.persistentModelID == persistentID })?.id
        }
    }

    // MARK: - Watch folder monitoring

    func setupWatchFolderMonitoring() {
        folderMonitorService.onNewPDFsDetected = { [weak self] urls, labelIDs in
            self?.importFromWatchFolder(urls: urls, labelIDs: labelIDs)
        }
        refreshWatchFolderMonitors()
    }

    func refreshWatchFolderMonitors() {
        for folder in allWatchFolders {
            if folder.isEnabled && folderMonitorService.folderExists(at: folder.folderPath) {
                if !folderMonitorService.isMonitoring(id: folder.id) {
                    folderMonitorService.startMonitoring(folder)
                } else {
                    folderMonitorService.updateLabelIDs(for: folder.id, labelIDs: folder.labelIDs)
                }
            } else {
                folderMonitorService.stopMonitoring(id: folder.id)
            }
        }

        // Stop monitors for watch folders that have been deleted
        let currentIDs = Set(allWatchFolders.map(\.id))
        for folder in allWatchFolders where !currentIDs.contains(folder.id) {
            folderMonitorService.stopMonitoring(id: folder.id)
        }

        recomputeWatchFolderStatuses()
    }

    func tearDownWatchFolderMonitoring() {
        folderMonitorService.stopAll()
    }

    private func importFromWatchFolder(urls: [URL], labelIDs: [UUID]) {
        guard let modelContext, let libraryURL else { return }

        let labelsToAssign = allLabels.filter { labelIDs.contains($0.id) }

        Task { @MainActor [weak self] in
            let result = await ImportPDFDocumentsUseCase.execute(
                urls: urls,
                into: libraryURL,
                autoAssignLabels: labelsToAssign,
                using: modelContext
            )

            if result.importedCount > 0 {
                self?.importSummaryMessage = "Watch folder: imported \(result.importedCount) document\(result.importedCount == 1 ? "" : "s")."
            }
        }
    }

    private func recomputeWatchFolderStatuses() {
        var statuses: [UUID: WatchFolderStatus] = [:]
        for folder in allWatchFolders {
            if !folderMonitorService.folderExists(at: folder.folderPath) {
                statuses[folder.id] = .pathInvalid
            } else if !folder.isEnabled {
                statuses[folder.id] = .paused
            } else {
                statuses[folder.id] = .monitoring
            }
        }
        watchFolderStatuses = statuses
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

    var pendingDroppedLabelAssignmentBinding: Binding<Bool> {
        optionalPresenceBinding(for: \.pendingDroppedLabelAssignment)
    }

    /// Returns a `Binding<Bool>` that is `true` when the optional property is non-nil,
    /// and sets it to `nil` when the binding is set to `false`.
    private func optionalPresenceBinding<T>(
        for keyPath: ReferenceWritableKeyPath<LibraryCoordinator, T?>
    ) -> Binding<Bool> {
        Binding(
            get: { self[keyPath: keyPath] != nil },
            set: { newValue in
                if !newValue {
                    self[keyPath: keyPath] = nil
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
        let selectionLabel = self.selectedSection?.rawValue ?? "smartFolder"
        Self.performanceLogger.log(
            "[Performance][Filter] selection=\(selectionLabel, privacy: .public) source=\(sourceCount) filtered=\(filteredCount) query=\(queryLength) labels=\(activeLabelFilters) duration=\(elapsedMs, format: .fixed(precision: 2))ms"
        )
        #endif
    }
}

extension LibrarySidebarCounts {
    static let empty = LibrarySidebarCounts(activeDocuments: [], trashedCount: 0, labels: [], recentLimit: 10, labelSourceDocuments: [], activeLabelFilterIDs: [])
}
