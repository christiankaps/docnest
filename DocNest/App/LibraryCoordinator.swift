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
/// Central UI-state coordinator for the open-library experience.
///
/// The coordinator sits between persisted SwiftData models and SwiftUI views.
/// It owns transient interaction state such as selection, filters, progress,
/// summary messages, derived sidebar counts, and watch-folder wiring while
/// delegating business behavior to dedicated use cases and services.
final class LibraryCoordinator {
    private static let performanceLogger = Logger(subsystem: "com.kaps.docnest", category: "performance")

    private struct DerivedStateResult: Sendable {
        let filteredDocumentIDs: [UUID]
        let smartFolderCounts: [UUID: Int]
        let sectionCounts: [LibrarySection: Int]
        let labelCounts: [UUID: Int]
    }

    private enum DerivedSidebarSelection: Sendable {
        case section(LibrarySection)
        case smartFolder(UUID)
    }

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
    var isInspectorCollapsed = false
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
    private(set) var filteredDocumentsVersion = 0
    private(set) var selectedDocuments: [DocumentRecord] = []
    private(set) var displayedSelectedDocuments: [DocumentRecord] = []
    private(set) var displayedShareURLs: [URL] = []
    private(set) var selectedDocumentIDsToDrag: [UUID] = []
    private(set) var sidebarCounts = LibrarySidebarCounts.empty
    private(set) var existingContentHashes: Set<String> = []
    private var labelsByUUID: [UUID: LabelTag] = [:]
    private var labelUUIDByPersistentID: [PersistentIdentifier: UUID] = [:]
    private var smartFoldersByPersistentID: [PersistentIdentifier: SmartFolder] = [:]
    private var documentUUIDByPersistentID: [PersistentIdentifier: UUID] = [:]
    private var documentByUUID: [UUID: DocumentRecord] = [:]
    private var filteredDocumentByPersistentID: [PersistentIdentifier: DocumentRecord] = [:]
    private var filteredDocumentOrderByPersistentID: [PersistentIdentifier: Int] = [:]
    private var activeDocumentSnapshots: [SearchDocumentsUseCase.Snapshot] = []
    private var trashedDocumentSnapshots: [SearchDocumentsUseCase.Snapshot] = []

    // MARK: - Internal
    private var activeImportTask: Task<Void, Never>?
    private let watchFolderController = WatchFolderController()
    private var pendingLabelFilterApplyTask: Task<Void, Never>?
    private var pendingDisplayedSelectionTask: Task<Void, Never>?
    private var pendingSearchRecomputeTask: Task<Void, Never>?
    private var pendingDerivedStateTask: Task<Void, Never>?
    private var pendingDisplayedShareURLsTask: Task<Void, Never>?
    private let labelFilterApplyDelay: Duration = .milliseconds(75)
    private let displayedSelectionDelay: Duration = .milliseconds(65)
    private let searchRecomputeDelay: Duration = .milliseconds(85)
    private var lastSelectionInteractionStart: TimeInterval?
    private var isImmediateDisplayedSelectionPending = false
    private var derivedStateGeneration = 0
    let recentDocumentLimit = 10

    deinit {
        MainActor.assumeIsolated {
            activeImportTask?.cancel()
            activeOCRTask?.cancel()
            pendingLabelFilterApplyTask?.cancel()
            pendingDisplayedSelectionTask?.cancel()
            pendingSearchRecomputeTask?.cancel()
            pendingDerivedStateTask?.cancel()
            pendingDisplayedShareURLsTask?.cancel()
            watchFolderController.tearDown()
        }
    }

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

    var isInspectorSelectionPending: Bool {
        selectedDocumentIDs != Set(displayedSelectedDocuments.map(\.persistentModelID))
    }

    var immediateSelectionDocuments: [DocumentRecord] {
        selectedDocuments
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
           let folder = smartFoldersByPersistentID[folderID] {
            return resolvedLabelPersistentIDs(from: folder.labelIDs)
        }
        return labelFilterSelection.visualSelection
    }

    // MARK: - Data ingestion

    /// Synchronizes the latest queried SwiftData models into coordinator-managed
    /// UI state and recomputes all derived views when needed.
    func ingest(allDocuments: [DocumentRecord], allLabels: [LabelTag], allSmartFolders: [SmartFolder] = [], allLabelGroups: [LabelGroup] = [], allWatchFolders: [WatchFolder] = []) {
        syncMetadata(labels: allLabels, smartFolders: allSmartFolders, labelGroups: allLabelGroups, recompute: false)
        syncWatchFolders(allWatchFolders, refreshMonitors: false)
        syncDocuments(allDocuments, recompute: true)
    }

    func syncDocuments(_ allDocuments: [DocumentRecord], recompute: Bool = true) {
        documentUUIDByPersistentID = Dictionary(uniqueKeysWithValues: allDocuments.map { ($0.persistentModelID, $0.id) })
        documentByUUID = Dictionary(uniqueKeysWithValues: allDocuments.map { ($0.id, $0) })

        var active: [DocumentRecord] = []
        var trashed: [DocumentRecord] = []
        var activeSnapshots: [SearchDocumentsUseCase.Snapshot] = []
        var trashedSnapshots: [SearchDocumentsUseCase.Snapshot] = []
        active.reserveCapacity(allDocuments.count)
        trashed.reserveCapacity(min(allDocuments.count / 8, allDocuments.count))
        activeSnapshots.reserveCapacity(allDocuments.count)
        trashedSnapshots.reserveCapacity(min(allDocuments.count / 8, allDocuments.count))

        for document in allDocuments {
            let snapshot = SearchDocumentsUseCase.Snapshot(
                documentID: document.id,
                labelIDs: Set(document.labels.map(\.id)),
                title: document.title,
                originalFileName: document.originalFileName,
                labelNames: document.labels.map(\.name),
                fullText: document.fullText
            )
            if document.trashedAt == nil {
                active.append(document)
                activeSnapshots.append(snapshot)
            } else {
                trashed.append(document)
                trashedSnapshots.append(snapshot)
            }
        }

        activeDocuments = active
        trashedDocuments = trashed
        activeDocumentSnapshots = activeSnapshots
        trashedDocumentSnapshots = trashedSnapshots
        existingContentHashes = Set(allDocuments.lazy.map(\.contentHash))
        recomputeSelectedDocuments()

        if recompute {
            recomputeFilteredDocuments()
        }
    }

    func syncMetadata(
        labels: [LabelTag],
        smartFolders: [SmartFolder],
        labelGroups: [LabelGroup],
        recompute: Bool = true
    ) {
        allLabels = labels
        allSmartFolders = smartFolders
        allLabelGroups = labelGroups
        labelsByUUID = Dictionary(uniqueKeysWithValues: labels.map { ($0.id, $0) })
        labelUUIDByPersistentID = Dictionary(uniqueKeysWithValues: labels.map { ($0.persistentModelID, $0.id) })
        smartFoldersByPersistentID = Dictionary(uniqueKeysWithValues: smartFolders.map { ($0.persistentModelID, $0) })

        if recompute {
            recomputeFilteredDocuments()
        }
    }

    func syncWatchFolders(_ watchFolders: [WatchFolder], refreshMonitors: Bool = true) {
        allWatchFolders = watchFolders
        if refreshMonitors {
            refreshWatchFolderMonitors()
        }
    }

    // MARK: - Recomputation

    /// Rebuilds the document list, sidebar counts, and label counts from the
    /// current selection, filter, and search state.
    ///
    /// The expensive filtering work happens off the main actor and is guarded
    /// by generation checks so stale computations do not overwrite newer UI state.
    func recomputeFilteredDocuments() {
        #if DEBUG
        let startTime = Date().timeIntervalSinceReferenceDate
        #endif

        pendingDerivedStateTask?.cancel()
        derivedStateGeneration += 1
        let generation = derivedStateGeneration

        let selectedLabelUUIDs = resolvedLabelUUIDs(from: labelFilterSelection.appliedSelection)
        let sidebarSelection = derivedSidebarSelection
        let smartFolderLabelUUIDs = Dictionary(
            uniqueKeysWithValues: allSmartFolders.map { ($0.id, Set($0.labelIDs)) }
        )
        let allLabelIDs = allLabels.map(\.id)
        let recentLimit = recentDocumentLimit
        let query = searchText
        let activeSnapshots = activeDocumentSnapshots
        let trashedSnapshots = trashedDocumentSnapshots

        pendingDerivedStateTask = Task(priority: .userInitiated) { [weak self] in
            let result: DerivedStateResult
            do {
                result = try Self.buildDerivedState(
                    sidebarSelection: sidebarSelection,
                    query: query,
                    selectedLabelUUIDs: selectedLabelUUIDs,
                    activeDocuments: activeSnapshots,
                    trashedDocuments: trashedSnapshots,
                    smartFolderLabelUUIDs: smartFolderLabelUUIDs,
                    allLabelIDs: allLabelIDs,
                    recentLimit: recentLimit
                )
            } catch is CancellationError {
                return
            } catch {
                return
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                guard !Task.isCancelled else { return }
                guard self.derivedStateGeneration == generation else { return }

                self.smartFolderCounts = Dictionary(uniqueKeysWithValues: self.allSmartFolders.map { folder in
                    (folder.persistentModelID, result.smartFolderCounts[folder.id, default: 0])
                })
                self.filteredDocuments = result.filteredDocumentIDs.compactMap { self.documentByUUID[$0] }
                self.filteredDocumentsVersion &+= 1
                self.sidebarCounts = LibrarySidebarCounts(
                    sectionCounts: result.sectionCounts,
                    labelCounts: Dictionary(uniqueKeysWithValues: self.allLabels.map { label in
                        (label.persistentModelID, result.labelCounts[label.id, default: 0])
                    })
                )
                self.rebuildFilteredDocumentLookups()
                self.pruneSelectedDocumentIDs()

                #if DEBUG
                self.debugLogFilterTiming(
                    startTime: startTime,
                    sourceCount: Self.derivedSourceCount(
                        for: sidebarSelection,
                        activeCount: activeSnapshots.count,
                        trashedCount: trashedSnapshots.count,
                        recentLimit: recentLimit,
                        activeDocuments: activeSnapshots,
                        smartFolderLabelUUIDs: smartFolderLabelUUIDs
                    ),
                    filteredCount: self.filteredDocuments.count,
                    queryLength: query.count,
                    activeLabelFilters: self.labelFilterSelection.appliedSelection.count
                )
                #endif
            }
        }
    }

    private func resolvedLabelPersistentIDs(from uuids: [UUID]) -> Set<PersistentIdentifier> {
        var result = Set<PersistentIdentifier>()
        for uuid in uuids {
            if let label = labelsByUUID[uuid] {
                result.insert(label.persistentModelID)
            }
        }
        return result
    }

    private func resolvedLabelUUIDs(from persistentIDs: Set<PersistentIdentifier>) -> Set<UUID> {
        Set(persistentIDs.compactMap { labelUUIDByPersistentID[$0] })
    }

    private var derivedSidebarSelection: DerivedSidebarSelection {
        switch sidebarSelection {
        case .section(let section):
            .section(section)
        case .smartFolder(let persistentID):
            if let folder = smartFoldersByPersistentID[persistentID] {
                .smartFolder(folder.id)
            } else {
                .section(.allDocuments)
            }
        }
    }

    nonisolated private static func buildDerivedState(
        sidebarSelection: DerivedSidebarSelection,
        query: String,
        selectedLabelUUIDs: Set<UUID>,
        activeDocuments: [SearchDocumentsUseCase.Snapshot],
        trashedDocuments: [SearchDocumentsUseCase.Snapshot],
        smartFolderLabelUUIDs: [UUID: Set<UUID>],
        allLabelIDs: [UUID],
        recentLimit: Int
    ) throws -> DerivedStateResult {
        let sectionDocuments: [SearchDocumentsUseCase.Snapshot]

        switch sidebarSelection {
        case .section(.allDocuments):
            sectionDocuments = activeDocuments
        case .section(.recent):
            sectionDocuments = Array(activeDocuments.prefix(recentLimit))
        case .section(.needsLabels):
            sectionDocuments = activeDocuments.filter { $0.labelIDs.isEmpty }
        case .section(.bin):
            sectionDocuments = trashedDocuments
        case .smartFolder(let folderID):
            let folderLabels = smartFolderLabelUUIDs[folderID] ?? []
            sectionDocuments = try SearchDocumentsUseCase.filter(
                activeDocuments,
                query: "",
                selectedLabelIDs: folderLabels
            )
        }

        let filteredDocuments: [SearchDocumentsUseCase.Snapshot]
        switch sidebarSelection {
        case .smartFolder:
            filteredDocuments = sectionDocuments
        case .section:
            filteredDocuments = try SearchDocumentsUseCase.filter(
                sectionDocuments,
                query: query,
                selectedLabelIDs: selectedLabelUUIDs
            )
        }

        let smartFolderCounts = computeSmartFolderCounts(
            activeDocuments: activeDocuments,
            smartFolderLabelUUIDs: smartFolderLabelUUIDs
        )

        var needsLabelsCount = 0
        for document in activeDocuments where document.labelIDs.isEmpty {
            needsLabelsCount += 1
        }

        var labelCounts = Dictionary(uniqueKeysWithValues: allLabelIDs.map { ($0, 0) })
        for (index, document) in sectionDocuments.enumerated() {
            if index.isMultiple(of: 64) {
                try Task.checkCancellation()
            }
            let matchesOtherFilters = selectedLabelUUIDs.allSatisfy { document.labelIDs.contains($0) }
            guard matchesOtherFilters else { continue }

            for labelID in document.labelIDs {
                labelCounts[labelID, default: 0] += 1
            }
        }

        return DerivedStateResult(
            filteredDocumentIDs: filteredDocuments.map(\.documentID),
            smartFolderCounts: smartFolderCounts,
            sectionCounts: [
                .allDocuments: activeDocuments.count,
                .recent: min(activeDocuments.count, recentLimit),
                .needsLabels: needsLabelsCount,
                .bin: trashedDocuments.count
            ],
            labelCounts: labelCounts
        )
    }

    nonisolated private static func derivedSourceCount(
        for selection: DerivedSidebarSelection,
        activeCount: Int,
        trashedCount: Int,
        recentLimit: Int,
        activeDocuments: [SearchDocumentsUseCase.Snapshot],
        smartFolderLabelUUIDs: [UUID: Set<UUID>]
    ) -> Int {
        switch selection {
        case .section(.allDocuments):
            return activeCount
        case .section(.recent):
            return min(activeCount, recentLimit)
        case .section(.needsLabels):
            return activeDocuments.filter { $0.labelIDs.isEmpty }.count
        case .section(.bin):
            return trashedCount
        case .smartFolder(let folderID):
            let labelIDs = smartFolderLabelUUIDs[folderID] ?? []
            return (try? SearchDocumentsUseCase.filter(
                activeDocuments,
                query: "",
                selectedLabelIDs: labelIDs
            ))?.count ?? 0
        }
    }

    nonisolated private static func computeSmartFolderCounts(
        activeDocuments: [SearchDocumentsUseCase.Snapshot],
        smartFolderLabelUUIDs: [UUID: Set<UUID>]
    ) -> [UUID: Int] {
        guard !smartFolderLabelUUIDs.isEmpty else { return [:] }

        var counts = Dictionary(uniqueKeysWithValues: smartFolderLabelUUIDs.keys.map { ($0, 0) })
        var candidateFoldersByLabelID: [UUID: [UUID]] = [:]
        var requiredLabelCounts: [UUID: Int] = [:]
        var emptyFolderIDs: [UUID] = []

        for (folderID, labelIDs) in smartFolderLabelUUIDs {
            requiredLabelCounts[folderID] = labelIDs.count
            if labelIDs.isEmpty {
                emptyFolderIDs.append(folderID)
                continue
            }

            for labelID in labelIDs {
                candidateFoldersByLabelID[labelID, default: []].append(folderID)
            }
        }

        if !emptyFolderIDs.isEmpty {
            for folderID in emptyFolderIDs {
                counts[folderID] = activeDocuments.count
            }
        }

        for (index, document) in activeDocuments.enumerated() {
            if index.isMultiple(of: 64) && Task.isCancelled {
                return counts
            }
            guard !document.labelIDs.isEmpty else { continue }

            var matchedRequirements: [UUID: Int] = [:]
            for labelID in document.labelIDs {
                guard let folderIDs = candidateFoldersByLabelID[labelID] else { continue }
                for folderID in folderIDs {
                    matchedRequirements[folderID, default: 0] += 1
                }
            }

            for (folderID, matchedCount) in matchedRequirements {
                if matchedCount == requiredLabelCounts[folderID] {
                    counts[folderID, default: 0] += 1
                }
            }
        }

        return counts
    }

    private func rebuildFilteredDocumentLookups() {
        filteredDocumentByPersistentID = Dictionary(
            uniqueKeysWithValues: filteredDocuments.map { ($0.persistentModelID, $0) }
        )
        filteredDocumentOrderByPersistentID = Dictionary(
            uniqueKeysWithValues: filteredDocuments.enumerated().map { ($0.element.persistentModelID, $0.offset) }
        )
    }

    func recomputeSelectedDocuments() {
        let knownSelectionIDs = Set(
            selectedDocumentIDs.filter { documentUUIDByPersistentID[$0] != nil }
        )
        if knownSelectionIDs != selectedDocumentIDs {
            selectedDocumentIDs = knownSelectionIDs
        }

        let explicitSelection = selectedDocumentIDs.compactMap { selectedDocument(for: $0) }
            .sorted {
                compareSelectionOrder($0, $1)
            }

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
        selectedDocumentIDsToDrag = selectedDocuments.compactMap { documentUUIDByPersistentID[$0.persistentModelID] }
    }

    private func selectedDocument(for persistentID: PersistentIdentifier) -> DocumentRecord? {
        if let filteredDocument = filteredDocumentByPersistentID[persistentID] {
            return filteredDocument
        }

        guard let documentID = documentUUIDByPersistentID[persistentID] else {
            return nil
        }

        return documentByUUID[documentID]
    }

    private func compareSelectionOrder(_ lhs: DocumentRecord, _ rhs: DocumentRecord) -> Bool {
        let leftIndex = filteredDocumentOrderByPersistentID[lhs.persistentModelID] ?? .max
        let rightIndex = filteredDocumentOrderByPersistentID[rhs.persistentModelID] ?? .max
        if leftIndex != rightIndex {
            return leftIndex < rightIndex
        }

        let titleComparison = lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        if titleComparison != .orderedSame {
            return titleComparison == .orderedAscending
        }

        return lhs.importedAt < rhs.importedAt
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

    /// Coalesces inspector and passive share updates so row highlighting can update immediately on click.
    func scheduleDisplayedSelectionUpdate() {
        pendingDisplayedSelectionTask?.cancel()

        if isImmediateDisplayedSelectionPending {
            isImmediateDisplayedSelectionPending = false
            syncDisplayedSelectionImmediately()
            return
        }

        pendingDisplayedSelectionTask = Task { @MainActor in
            try? await Task.sleep(for: displayedSelectionDelay)

            guard !Task.isCancelled else {
                return
            }

            syncDisplayedSelectionImmediately()
        }
    }

    func cancelPendingDisplayedSelectionUpdate() {
        pendingDisplayedSelectionTask?.cancel()
        pendingDisplayedShareURLsTask?.cancel()
    }

    /// Debounces text search updates to keep typing and row highlighting responsive.
    func scheduleSearchRecompute() {
        pendingSearchRecomputeTask?.cancel()
        pendingSearchRecomputeTask = Task { @MainActor in
            try? await Task.sleep(for: searchRecomputeDelay)

            guard !Task.isCancelled else {
                return
            }

            recomputeFilteredDocuments()
            pruneSelectedDocumentIDs()
        }
    }

    func cancelPendingSearchRecompute() {
        pendingSearchRecomputeTask?.cancel()
    }

    func cancelPendingDerivedStateRefresh() {
        pendingDerivedStateTask?.cancel()
    }

    func tearDown() {
        cancelPendingLabelFilter()
        cancelPendingDisplayedSelectionUpdate()
        cancelPendingSearchRecompute()
        cancelPendingDerivedStateRefresh()
        cancelImport()
        cancelOCR()
        tearDownWatchFolderMonitoring()
    }

    func syncDisplayedSelectionImmediately() {
        displayedSelectedDocuments = selectedDocuments
        displayedShareURLs = []
        resolveDisplayedShareURLs(for: displayedSelectedDocuments)
        logDisplayedSelectionCommit()
    }

    private func resolveDisplayedShareURLs(for documents: [DocumentRecord]) {
        pendingDisplayedShareURLsTask?.cancel()

        guard let libraryURL else {
            displayedShareURLs = []
            return
        }

        let candidates = documents.compactMap { document -> (UUID, String)? in
            guard let path = document.storedFilePath else { return nil }
            return (document.id, path)
        }

        pendingDisplayedShareURLsTask = Task(priority: .utility) { [weak self] in
            var resolvedURLs: [URL] = []
            resolvedURLs.reserveCapacity(candidates.count)

            for (_, path) in candidates {
                guard !Task.isCancelled else { return }
                let exists = await DocumentStorageService.fileExistsAsync(at: path, libraryURL: libraryURL)
                guard exists else { continue }
                resolvedURLs.append(DocumentStorageService.fileURL(for: path, libraryURL: libraryURL))
            }

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard let self else { return }
                guard !Task.isCancelled else { return }
                let currentIDs = self.displayedSelectedDocuments.map(\.id)
                let targetIDs = candidates.map(\.0)
                guard currentIDs == targetIDs else { return }
                self.displayedShareURLs = resolvedURLs
            }
        }
    }

    func beginSelectionInteraction() {
        lastSelectionInteractionStart = Date().timeIntervalSinceReferenceDate
        isImmediateDisplayedSelectionPending = true
    }

    func scheduleSelectionVisualResponseLog() {
        let startTime = lastSelectionInteractionStart
        Task { @MainActor in
            await Task.yield()
            guard let startTime else { return }
            let elapsedMs = (Date().timeIntervalSinceReferenceDate - startTime) * 1000
            Self.performanceLogger.log(
                "[Performance][SelectionVisual] count=\(self.selectedDocumentIDs.count) duration=\(elapsedMs, format: .fixed(precision: 2))ms"
            )
        }
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
            recomputeFilteredDocuments()
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    func restoreAllFromBin() {
        guard let modelContext else { return }
        do {
            try DeleteDocumentsUseCase.restoreFromBin(trashedDocuments, using: modelContext)
            recomputeFilteredDocuments()
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
            recomputeFilteredDocuments()
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    func moveToBin(_ documents: [DocumentRecord]) {
        guard let modelContext else { return }
        do {
            try DeleteDocumentsUseCase.moveToBin(documents, using: modelContext)
            recomputeFilteredDocuments()
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
            recomputeFilteredDocuments()
        } catch {
            importSummaryMessage = error.localizedDescription
        }
    }

    func assignDroppedLabelToDocuments(_ labelID: UUID, documents: [DocumentRecord]) -> Bool {
        guard let modelContext else { return false }

        let activeDocuments = documents.filter { $0.trashedAt == nil }
        guard !activeDocuments.isEmpty else { return false }

        guard let label = labelsByUUID[labelID] else {
            return false
        }

        do {
            try ManageLabelsUseCase.assign(label, to: activeDocuments, using: modelContext)
            recomputeFilteredDocuments()
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
              let labelUUID = labelUUIDByPersistentID[pending.labelID],
              let label = labelsByUUID[labelUUID] else {
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
            recomputeFilteredDocuments()
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
            recomputeFilteredDocuments()
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
           let folder = smartFoldersByPersistentID[folderID] {
            let folderLabelUUIDs = Set(folder.labelIDs)
            activeFilterLabels = allLabels.filter { folderLabelUUIDs.contains($0.id) }
        } else {
            activeFilterLabels = allLabels.filter { label in
                labelFilterSelection.visualSelection.contains(label.persistentModelID)
            }
        }

        importProgress = ImportProgress(total: 0, completed: 0)

        // Manual imports and drop/paste/service imports all converge here so
        // they share progress reporting, active-filter label assignment, and
        // summary-message behavior.
        activeImportTask = Task { @MainActor [weak self] in
            let importResult = await ImportPDFDocumentsUseCase.execute(
                urls: urls,
                into: libraryURL,
                autoAssignLabels: activeFilterLabels,
                existingContentHashes: self?.existingContentHashes ?? [],
                using: modelContext
            ) { [weak self] completed, total in
                self?.importProgress = ImportProgress(total: total, completed: completed)
            }

            guard !Task.isCancelled else {
                self?.activeImportTask = nil
                return
            }

            self?.importProgress = nil
            self?.activeImportTask = nil

            if importResult.hasUserMessage {
                self?.importSummaryMessage = importResult.summaryMessage
            }
            self?.recomputeFilteredDocuments()
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

            guard !Task.isCancelled else {
                self?.activeOCRTask = nil
                return
            }

            self?.ocrProgress = nil
            self?.activeOCRTask = nil
            self?.recomputeFilteredDocuments()
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
        recomputeFilteredDocuments()
    }

    func cancelOCR() {
        activeOCRTask?.cancel()
        activeOCRTask = nil
        ocrProgress = nil
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
            recomputeFilteredDocuments()
            return true
        } catch {
            importSummaryMessage = error.localizedDescription
            return false
        }
    }

    func prefillLabelIDsForNewSmartFolder() -> [UUID] {
        labelFilterSelection.appliedSelection.compactMap { labelUUIDByPersistentID[$0] }
    }

    // MARK: - Watch folder monitoring

    /// Sets up callbacks so watch-folder detections re-enter the same import
    /// pipeline used by manual imports.
    func setupWatchFolderMonitoring() {
        watchFolderController.onImportRequested = { [weak self] urls, labelIDs in
            self?.importFromWatchFolder(urls: urls, labelIDs: labelIDs)
        }
        refreshWatchFolderMonitors()
    }

    func refreshWatchFolderMonitors() {
        watchFolderController.refresh(with: allWatchFolders)
        watchFolderStatuses = watchFolderController.statuses
    }

    func tearDownWatchFolderMonitoring() {
        watchFolderController.tearDown()
        watchFolderStatuses = [:]
    }

    private func importFromWatchFolder(urls: [URL], labelIDs: [UUID]) {
        guard let modelContext, let libraryURL else { return }

        let labelsToAssign = allLabels.filter { labelIDs.contains($0.id) }

        Task { @MainActor [weak self] in
            let result = await ImportPDFDocumentsUseCase.execute(
                urls: urls,
                into: libraryURL,
                autoAssignLabels: labelsToAssign,
                existingContentHashes: self?.existingContentHashes ?? [],
                using: modelContext
            )

            if result.importedCount > 0 {
                self?.importSummaryMessage = "Watch folder: imported \(result.importedCount) document\(result.importedCount == 1 ? "" : "s")."
            }
            self?.recomputeFilteredDocuments()
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
              let labelUUID = labelUUIDByPersistentID[pending.labelID],
              let label = labelsByUUID[labelUUID] else {
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

    private func logDisplayedSelectionCommit() {
        #if DEBUG
        let elapsedMs: Double
        if let startTime = lastSelectionInteractionStart {
            elapsedMs = (Date().timeIntervalSinceReferenceDate - startTime) * 1000
        } else {
            elapsedMs = 0
        }
        Self.performanceLogger.log(
            "[Performance][SelectionDeferred] displayed=\(self.displayedSelectedDocuments.count) shareURLs=\(self.displayedShareURLs.count) duration=\(elapsedMs, format: .fixed(precision: 2))ms"
        )
        #endif
    }
}

extension LibrarySidebarCounts {
    static let empty = LibrarySidebarCounts(activeDocuments: [], trashedCount: 0, labels: [], recentLimit: 10, labelSourceDocuments: [], activeLabelFilterIDs: [])
}

@MainActor
private final class WatchFolderController {
    private let folderMonitorService = FolderMonitorService()

    var onImportRequested: ((_ urls: [URL], _ labelIDs: [UUID]) -> Void)? {
        didSet {
            folderMonitorService.onNewPDFsDetected = onImportRequested
        }
    }

    private(set) var statuses: [UUID: WatchFolderStatus] = [:]

    func refresh(with watchFolders: [WatchFolder]) {
        let currentIDs = Set(watchFolders.map(\.id))

        for folder in watchFolders {
            if folder.isEnabled && folderMonitorService.folderExists(at: folder.folderPath) {
                if folderMonitorService.isMonitoring(id: folder.id),
                   folderMonitorService.monitoredFolderPath(for: folder.id) == folder.folderPath {
                    folderMonitorService.updateLabelIDs(for: folder.id, labelIDs: folder.labelIDs)
                } else {
                    folderMonitorService.stopMonitoring(id: folder.id)
                    folderMonitorService.startMonitoring(folder)
                }
            } else {
                folderMonitorService.stopMonitoring(id: folder.id)
            }
        }

        for monitoredID in folderMonitorService.monitoredIDs where !currentIDs.contains(monitoredID) {
            folderMonitorService.stopMonitoring(id: monitoredID)
        }

        recomputeStatuses(for: watchFolders)
    }

    func tearDown() {
        folderMonitorService.stopAll()
        statuses = [:]
    }

    private func recomputeStatuses(for watchFolders: [WatchFolder]) {
        var nextStatuses: [UUID: WatchFolderStatus] = [:]
        for folder in watchFolders {
            if !folderMonitorService.folderExists(at: folder.folderPath) {
                nextStatuses[folder.id] = .pathInvalid
            } else if !folder.isEnabled {
                nextStatuses[folder.id] = .paused
            } else {
                nextStatuses[folder.id] = .monitoring
            }
        }
        statuses = nextStatuses
    }
}
