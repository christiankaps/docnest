import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    let libraryURL: URL
    @ObservedObject var librarySession: LibrarySessionController

    @State private var coordinator = LibraryCoordinator()
    @State private var thumbnailCache = ThumbnailCache()
    @State private var quickLook = QuickLookCoordinator()
    @State private var inspectorVisibilityProgress = 1.0

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DocumentRecord.importedAt, order: .reverse)
    private var allDocuments: [DocumentRecord]

    @Query(sort: [SortDescriptor(\LabelTag.sortOrder, order: .forward), SortDescriptor(\LabelTag.name, order: .forward)])
    private var allLabels: [LabelTag]

    @Query(sort: \SmartFolder.sortOrder, order: .forward)
    private var allSmartFolders: [SmartFolder]

    @Query(sort: \LabelGroup.sortOrder, order: .forward)
    private var allLabelGroups: [LabelGroup]

    @Query(sort: \WatchFolder.sortOrder, order: .forward)
    private var allWatchFolders: [WatchFolder]

    var body: some View {
        HStack(spacing: 0) {
            LibrarySidebarView()
                .frame(width: AppSplitViewLayout.sidebarWidth)

            Divider()

            documentListPanel
                .frame(minWidth: AppSplitViewLayout.documentListMinWidth)

            Divider()
                .opacity(inspectorDividerOpacity)

            DocumentInspectorView(
                documents: coordinator.displayedSelectedDocuments,
                libraryURL: libraryURL,
                isTransitioningSelection: coordinator.isInspectorSelectionPending
            )
            .frame(width: inspectorWidth)
            .opacity(inspectorContentOpacity)
            .clipped()
            .allowsHitTesting(!coordinator.isInspectorCollapsed)
            .accessibilityHidden(coordinator.isInspectorCollapsed)
            .compositingGroup()
        }
        .animation(.easeInOut(duration: 0.16), value: inspectorVisibilityProgress)
        .background(Color(nsColor: .windowBackgroundColor))
        .environment(coordinator)
        .environment(thumbnailCache)
        .environment(quickLook)
        .toolbar { toolbarContent }
        .modifier(RootViewImportModifier(coordinator: coordinator))
        .modifier(RootViewDialogsModifier(coordinator: coordinator, allDocuments: allDocuments))
        .modifier(RootViewChangeHandlers(coordinator: coordinator, allDocuments: allDocuments, allLabels: allLabels, allSmartFolders: allSmartFolders, allLabelGroups: allLabelGroups, allWatchFolders: allWatchFolders))
        .focusedSceneValue(\.exportDocumentsAction) {
            coordinator.exportDocuments(coordinator.displayedSelectedDocuments)
        }
        .focusedSceneValue(\.pasteDocumentsAction) {
            pasteDocumentsFromPasteboard()
        }
        .focusedSceneValue(\.selectAllDocumentsAction) {
            selectAllFilteredDocuments()
        }
        .focusedSceneValue(\.toggleInspectorAction) {
            coordinator.isInspectorCollapsed.toggle()
        }
        .focusedSceneValue(\.isInspectorCollapsed, coordinator.isInspectorCollapsed)
        .task {
            coordinator.libraryURL = libraryURL
            coordinator.modelContext = modelContext
            inspectorVisibilityProgress = coordinator.isInspectorCollapsed ? 0 : 1
            AppSettingsController.shared.setActiveLibraryContext(
                coordinator: coordinator,
                modelContainer: librarySession.modelContainer
            )
            coordinator.ingest(allDocuments: allDocuments, allLabels: allLabels, allSmartFolders: allSmartFolders, allLabelGroups: allLabelGroups, allWatchFolders: allWatchFolders)
            coordinator.runOCRBackfill(documents: allDocuments, libraryURL: libraryURL, modelContext: modelContext)
            coordinator.setupWatchFolderMonitoring()
            // Import any URLs that arrived before the library was ready
            let pending = librarySession.drainPendingImportURLs()
            if !pending.isEmpty {
                coordinator.importDocuments(from: pending)
            }
        }
        .onChange(of: librarySession.pendingImportURLs) {
            let pending = librarySession.drainPendingImportURLs()
            if !pending.isEmpty {
                coordinator.importDocuments(from: pending)
            }
        }
        .onChange(of: coordinator.isInspectorCollapsed) { _, isCollapsed in
            inspectorVisibilityProgress = isCollapsed ? 0 : 1
        }
    }

    private var inspectorWidth: Double {
        AppSplitViewLayout.inspectorWidth * inspectorVisibilityProgress
    }

    private var inspectorContentOpacity: Double {
        max(0, min(1, inspectorVisibilityProgress * 1.2))
    }

    private var inspectorDividerOpacity: Double {
        max(0, min(1, inspectorVisibilityProgress))
    }

    private var documentListPanel: some View {
        ZStack {
            DocumentListView()

            if coordinator.isDropTargeted {
                DocumentImportDropOverlay(
                    title: "Drop PDFs or Folders to Import",
                    message: "Files will be copied into the open library. Folders are scanned recursively for PDFs."
                )
                .padding(20)
            }

            if coordinator.isQuickLabelPickerPresented {
                Color.black.opacity(0.001)
                    .onTapGesture {
                        coordinator.isQuickLabelPickerPresented = false
                    }

                QuickLabelPickerView(
                    isPresented: Bindable(coordinator).isQuickLabelPickerPresented
                )
                .padding(.top, 80)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
                .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
            }
        }
        .animation(.easeOut(duration: 0.15), value: coordinator.isQuickLabelPickerPresented)
        .background(Color(nsColor: .windowBackgroundColor))
        .background { QuickLookPanelResponder(coordinator: quickLook) }
        .onDrop(of: [.fileURL], delegate: FileImportDropDelegate(coordinator: coordinator))
        .onChange(of: coordinator.displayedShareURLs) {
            quickLook.previewURLs = coordinator.displayedShareURLs
            quickLook.reloadIfVisible()
        }
    }

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                SearchToolbarField(
                    text: Bindable(coordinator).searchText,
                    focusRequestToken: coordinator.searchFocusRequestToken
                )
                .frame(width: 300)

                if let progress = coordinator.importProgress {
                    ImportProgressIndicator(progress: progress) {
                        coordinator.cancelImport()
                    }
                    .transition(.opacity)
                }

                if let ocrProgress = coordinator.ocrProgress {
                    OCRProgressIndicator(progress: ocrProgress) {
                        coordinator.cancelOCR()
                    }
                    .transition(.opacity)
                }
            }
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                coordinator.isImporting = true
            } label: {
                Label("Import PDFs", systemImage: "plus")
            }
        }

        ToolbarItem(placement: .secondaryAction) {
            Picker("View", selection: Bindable(coordinator).documentListViewMode) {
                Image(systemName: "list.bullet")
                    .accessibilityLabel("List view")
                    .tag(DocumentListViewMode.list)
                Image(systemName: "square.grid.2x2")
                    .accessibilityLabel("Thumbnail view")
                    .tag(DocumentListViewMode.thumbnails)
            }
            .pickerStyle(.segmented)
            .frame(width: 60)
            .help("Switch between list and thumbnail view")
        }

        ToolbarItem(placement: .secondaryAction) {
            ShareLink(items: coordinator.displayedShareURLs) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(coordinator.displayedShareURLs.isEmpty)
            .help("Share selected documents")
        }

        ToolbarItem(placement: .primaryAction) {
            Button {
                coordinator.isInspectorCollapsed.toggle()
            } label: {
                Label(
                    coordinator.isInspectorCollapsed ? "Show Details" : "Hide Details",
                    systemImage: "sidebar.right"
                )
            }
            .help("Toggle details column (Control-D)")
        }
    }

    private func pasteDocumentsFromPasteboard() {
        var urls: [URL] = []

        // Read file URLs (from Finder copy)
        if let fileURLs = NSPasteboard.general.readObjects(forClasses: [NSURL.self]) as? [URL] {
            urls.append(contentsOf: fileURLs)
        }

        // Read plain-text strings that may be web URLs (from browser copy)
        if let strings = NSPasteboard.general.readObjects(forClasses: [NSString.self]) as? [String] {
            for string in strings {
                let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
                if let url = URL(string: trimmed),
                   let scheme = url.scheme?.lowercased(),
                   (scheme == "http" || scheme == "https"),
                   !urls.contains(url) {
                    urls.append(url)
                }
            }
        }

        guard !urls.isEmpty else { return }
        coordinator.importDocuments(from: urls)
    }

    private func selectAllFilteredDocuments() {
        coordinator.beginSelectionInteraction()
        let documents = coordinator.filteredDocuments
        coordinator.selectedDocumentIDs = Set(documents.map(\.persistentModelID))
    }

}

private struct RootViewImportModifier: ViewModifier {
    let coordinator: LibraryCoordinator

    func body(content: Content) -> some View {
        content
            .fileImporter(
                isPresented: Bindable(coordinator).isImporting,
                allowedContentTypes: [.pdf, .zip],
                allowsMultipleSelection: true
            ) { result in
                switch result {
                case .success(let urls):
                    coordinator.importDocuments(from: urls)
                case .failure:
                    coordinator.importSummaryMessage = "The selected files could not be read."
                }
            }
            .modifier(SummaryToastModifier(coordinator: coordinator))
    }
}

private struct SummaryToastModifier: ViewModifier {
    let coordinator: LibraryCoordinator

    @State private var visibleMessage: String?
    @State private var dismissTask: Task<Void, Never>?

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .bottom) {
                if let message = visibleMessage {
                    SummaryToastView(message: message)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                        .onTapGesture {
                            dismissToast()
                        }
                }
            }
            .animation(.easeInOut(duration: 0.25), value: visibleMessage)
            .onChange(of: coordinator.importSummaryMessage) { _, newValue in
                if let msg = newValue {
                    showToast(msg)
                    coordinator.importSummaryMessage = nil
                }
            }
            .onChange(of: coordinator.exportSummaryMessage) { _, newValue in
                if let msg = newValue {
                    showToast(msg)
                    coordinator.exportSummaryMessage = nil
                }
            }
    }

    private func showToast(_ message: String) {
        dismissTask?.cancel()
        visibleMessage = message
        dismissTask = Task { @MainActor in
            try? await Task.sleep(for: .seconds(5))
            guard !Task.isCancelled else { return }
            visibleMessage = nil
        }
    }

    private func dismissToast() {
        dismissTask?.cancel()
        visibleMessage = nil
    }
}

private struct SummaryToastView: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.system(size: 12, weight: .medium))
            .foregroundStyle(.primary)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 8))
            .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
            .padding(.bottom, 16)
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
    let allSmartFolders: [SmartFolder]
    let allLabelGroups: [LabelGroup]
    let allWatchFolders: [WatchFolder]

    private var documentFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(allDocuments.count)
        for document in allDocuments {
            hasher.combine(document.persistentModelID)
            hasher.combine(document.trashedAt)
            hasher.combine(document.storedFilePath)
        }
        return hasher.finalize()
    }

    private var labelFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(allLabels.count)
        for label in allLabels {
            hasher.combine(label.persistentModelID)
            hasher.combine(label.name)
            hasher.combine(label.sortOrder)
            hasher.combine(label.groupID)
        }
        return hasher.finalize()
    }

    private var smartFolderFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(allSmartFolders.count)
        for folder in allSmartFolders {
            hasher.combine(folder.persistentModelID)
            hasher.combine(folder.name)
            hasher.combine(folder.icon)
            hasher.combine(folder.sortOrder)
            for labelID in folder.labelIDs {
                hasher.combine(labelID)
            }
        }
        return hasher.finalize()
    }

    private var labelGroupFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(allLabelGroups.count)
        for group in allLabelGroups {
            hasher.combine(group.persistentModelID)
            hasher.combine(group.name)
            hasher.combine(group.sortOrder)
        }
        return hasher.finalize()
    }

    private var watchFolderFingerprint: Int {
        var hasher = Hasher()
        hasher.combine(allWatchFolders.count)
        for folder in allWatchFolders {
            hasher.combine(folder.persistentModelID)
            hasher.combine(folder.name)
            hasher.combine(folder.icon)
            hasher.combine(folder.folderPath)
            hasher.combine(folder.isEnabled)
            hasher.combine(folder.sortOrder)
            for labelID in folder.labelIDs {
                hasher.combine(labelID)
            }
        }
        return hasher.finalize()
    }

    func body(content: Content) -> some View {
        content
            .modifier(ChangeHandlersNotifications(coordinator: coordinator))
            .modifier(ChangeHandlersData(
                coordinator: coordinator,
                allDocuments: allDocuments,
                allLabels: allLabels,
                allSmartFolders: allSmartFolders,
                allLabelGroups: allLabelGroups,
                allWatchFolders: allWatchFolders,
                documentFingerprint: documentFingerprint,
                labelFingerprint: labelFingerprint,
                smartFolderFingerprint: smartFolderFingerprint,
                labelGroupFingerprint: labelGroupFingerprint,
                watchFolderFingerprint: watchFolderFingerprint
            ))
    }
}

private struct ChangeHandlersNotifications: ViewModifier {
    let coordinator: LibraryCoordinator

    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: .docNestFocusSearch)) { _ in
                coordinator.searchFocusRequestToken += 1
            }
            .onReceive(NotificationCenter.default.publisher(for: .docNestQuickLabelPicker)) { _ in
                guard !coordinator.selectedDocuments.isEmpty,
                      !coordinator.isBinSelected else { return }
                coordinator.isQuickLabelPickerPresented = true
            }
            .onReceive(NotificationCenter.default.publisher(for: .docNestLabelManager)) { _ in
                AppSettingsController.shared.show(.labels)
            }
            .onReceive(NotificationCenter.default.publisher(for: .docNestWatchFolderSettings)) { _ in
                AppSettingsController.shared.show(.watchFolders)
            }
            .onDisappear {
                coordinator.cancelPendingLabelFilter()
                coordinator.cancelPendingDisplayedSelectionUpdate()
                coordinator.cancelPendingSearchRecompute()
                coordinator.cancelPendingDerivedStateRefresh()
                coordinator.tearDownWatchFolderMonitoring()
                AppSettingsController.shared.clearActiveLibraryContext()
            }
            .onChange(of: coordinator.labelFilterSelection.visualSelection) { _, newSelection in
                coordinator.scheduleLabelFilterApply(immediately: newSelection.isEmpty)
            }
            .onChange(of: coordinator.sidebarSelection) {
                coordinator.cancelPendingSearchRecompute()
                coordinator.recomputeFilteredDocuments()
                coordinator.pruneSelectedDocumentIDs()
            }
            .onChange(of: coordinator.searchText) {
                coordinator.scheduleSearchRecompute()
            }
            .onChange(of: coordinator.selectedDocumentIDs) {
                coordinator.recomputeSelectedDocuments()
                coordinator.scheduleSelectionVisualResponseLog()
                coordinator.scheduleDisplayedSelectionUpdate()
            }
            .onChange(of: coordinator.labelFilterSelection.appliedSelection) {
                coordinator.cancelPendingSearchRecompute()
                coordinator.recomputeFilteredDocuments()
                coordinator.pruneSelectedDocumentIDs()
            }
    }
}

private struct ChangeHandlersData: ViewModifier {
    let coordinator: LibraryCoordinator
    let allDocuments: [DocumentRecord]
    let allLabels: [LabelTag]
    let allSmartFolders: [SmartFolder]
    let allLabelGroups: [LabelGroup]
    let allWatchFolders: [WatchFolder]
    let documentFingerprint: Int
    let labelFingerprint: Int
    let smartFolderFingerprint: Int
    let labelGroupFingerprint: Int
    let watchFolderFingerprint: Int
    @State private var pendingDocumentRefreshTask: Task<Void, Never>?
    @State private var pendingMetadataRefreshTask: Task<Void, Never>?
    @State private var pendingWatchFolderRefreshTask: Task<Void, Never>?

    private func scheduleDocumentRefresh() {
        pendingDocumentRefreshTask?.cancel()
        pendingDocumentRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            coordinator.syncDocuments(allDocuments)
        }
    }

    private func scheduleMetadataRefresh(syncLabels: Bool = false) {
        pendingMetadataRefreshTask?.cancel()
        pendingMetadataRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }

            if syncLabels {
                coordinator.syncLabelFilterSelections(Set(allLabels.map(\.persistentModelID)))
            }

            coordinator.syncMetadata(
                labels: allLabels,
                smartFolders: allSmartFolders,
                labelGroups: allLabelGroups
            )
        }
    }

    private func scheduleWatchFolderRefresh() {
        pendingWatchFolderRefreshTask?.cancel()
        pendingWatchFolderRefreshTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(50))
            guard !Task.isCancelled else { return }
            coordinator.syncWatchFolders(allWatchFolders)
        }
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: documentFingerprint) {
                scheduleDocumentRefresh()
            }
            .onChange(of: labelFingerprint) {
                scheduleMetadataRefresh(syncLabels: true)
            }
            .onChange(of: smartFolderFingerprint) {
                scheduleMetadataRefresh()
            }
            .onChange(of: labelGroupFingerprint) {
                scheduleMetadataRefresh()
            }
            .onChange(of: watchFolderFingerprint) {
                scheduleWatchFolderRefresh()
            }
            .onDisappear {
                pendingDocumentRefreshTask?.cancel()
                pendingMetadataRefreshTask?.cancel()
                pendingWatchFolderRefreshTask?.cancel()
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

private struct FileImportDropDelegate: DropDelegate {
    let coordinator: LibraryCoordinator

    func validateDrop(info: DropInfo) -> Bool {
        info.hasItemsConforming(to: [.fileURL])
    }

    func dropEntered(info: DropInfo) {
        coordinator.isDropTargeted = true
    }

    func dropExited(info: DropInfo) {
        coordinator.isDropTargeted = false
    }

    func performDrop(info: DropInfo) -> Bool {
        coordinator.isDropTargeted = false
        let providers = info.itemProviders(for: [.fileURL])
        guard !providers.isEmpty else { return false }

        Task { @MainActor in
            var urls: [URL] = []
            for provider in providers {
                if let url = await loadFileURL(from: provider) {
                    urls.append(url)
                }
            }
            guard !urls.isEmpty else { return }
            coordinator.importDocuments(from: urls)
        }
        return true
    }

    private func loadFileURL(from provider: NSItemProvider) async -> URL? {
        await withCheckedContinuation { continuation in
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { data, _ in
                if let data = data as? Data, let url = URL(dataRepresentation: data, relativeTo: nil) {
                    continuation.resume(returning: url)
                } else {
                    continuation.resume(returning: nil)
                }
            }
        }
    }
}

private struct ImportProgressIndicator: View {
    let progress: ImportProgress
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)

            if progress.total > 1 {
                Text("\(progress.completed)/\(progress.total)")
                    .font(.system(size: 11).monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop importing")
        }
        .help("Importing documents\u{2026}")
    }
}

private struct OCRProgressIndicator: View {
    let progress: OCRProgress
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            ProgressView()
                .controlSize(.small)

            Text("OCR \(progress.completed)/\(progress.total)")
                .font(.system(size: 11).monospacedDigit())
                .foregroundStyle(.secondary)

            Button(action: onCancel) {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .help("Stop OCR extraction")
        }
        .help("Extracting text\u{2026} \(progress.currentTitle)")
    }
}

#Preview {
    RootView(
        libraryURL: URL(fileURLWithPath: "/tmp/preview.docnestlibrary"),
        librarySession: LibrarySessionController()
    )
    .modelContainer(for: DocumentRecord.self, inMemory: true)
}
