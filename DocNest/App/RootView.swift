import SwiftUI
import SwiftData
import UniformTypeIdentifiers

struct RootView: View {
    let libraryURL: URL
    @ObservedObject var librarySession: LibrarySessionController

    @State private var coordinator = LibraryCoordinator()
    @State private var thumbnailCache = ThumbnailCache()
    @State private var quickLook = QuickLookCoordinator()

    @Environment(\.modelContext) private var modelContext

    @Query(sort: \DocumentRecord.importedAt, order: .reverse)
    private var allDocuments: [DocumentRecord]

    @Query(sort: [SortDescriptor(\LabelTag.sortOrder, order: .forward), SortDescriptor(\LabelTag.name, order: .forward)])
    private var allLabels: [LabelTag]

    @Query(sort: \SmartFolder.sortOrder, order: .forward)
    private var allSmartFolders: [SmartFolder]

    @Query(sort: \LabelGroup.sortOrder, order: .forward)
    private var allLabelGroups: [LabelGroup]

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
        .padding([.top, .bottom, .trailing], AppSplitViewLayout.windowContentInset)
        .environment(coordinator)
        .environment(thumbnailCache)
        .environment(quickLook)
        .toolbar { toolbarContent }
        .modifier(RootViewImportModifier(coordinator: coordinator))
        .modifier(RootViewDialogsModifier(coordinator: coordinator, allDocuments: allDocuments))
        .modifier(RootViewChangeHandlers(coordinator: coordinator, allDocuments: allDocuments, allLabels: allLabels, allSmartFolders: allSmartFolders, allLabelGroups: allLabelGroups))
        .focusedSceneValue(\.exportDocumentsAction) {
            coordinator.exportDocuments(coordinator.selectedDocuments)
        }
        .focusedSceneValue(\.pasteDocumentsAction) {
            pasteDocumentsFromPasteboard()
        }
        .task {
            coordinator.libraryURL = libraryURL
            coordinator.modelContext = modelContext
            coordinator.ingest(allDocuments: allDocuments, allLabels: allLabels, allSmartFolders: allSmartFolders, allLabelGroups: allLabelGroups)
            await ExtractDocumentTextUseCase.backfillAll(
                documents: allDocuments,
                libraryURL: libraryURL,
                modelContext: modelContext
            )
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
        }
        .background { QuickLookPanelResponder(coordinator: quickLook) }
        .onDrop(of: [.fileURL], delegate: FileImportDropDelegate(coordinator: coordinator))
        .onChange(of: coordinator.cachedShareURLs) {
            quickLook.previewURLs = coordinator.cachedShareURLs
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
                .frame(width: 280)

                if let progress = coordinator.importProgress {
                    ImportProgressIndicator(progress: progress) {
                        coordinator.cancelImport()
                    }
                    .transition(.opacity)
                }
            }
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

        ToolbarItem(placement: .primaryAction) {
            ShareLink(items: coordinator.cachedShareURLs) {
                Label("Share", systemImage: "square.and.arrow.up")
            }
            .disabled(coordinator.cachedShareURLs.isEmpty)
            .help("Share selected documents")
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
            hasher.combine(label.groupID)
        }
        return hasher.finalize()
    }

    private var smartFolderFingerprint: Int {
        var hasher = Hasher()
        for folder in allSmartFolders {
            hasher.combine(folder.persistentModelID)
            hasher.combine(folder.name)
            hasher.combine(folder.labelIDs)
            hasher.combine(folder.sortOrder)
        }
        return hasher.finalize()
    }

    private var labelGroupFingerprint: Int {
        var hasher = Hasher()
        for group in allLabelGroups {
            hasher.combine(group.persistentModelID)
            hasher.combine(group.name)
            hasher.combine(group.sortOrder)
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
            .onChange(of: coordinator.sidebarSelection) {
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
                coordinator.ingest(allDocuments: allDocuments, allLabels: allLabels, allSmartFolders: allSmartFolders, allLabelGroups: allLabelGroups)
            }
            .onChange(of: labelFingerprint) {
                coordinator.syncLabelFilterSelections(Set(allLabels.map(\.persistentModelID)))
                coordinator.ingest(allDocuments: allDocuments, allLabels: allLabels, allSmartFolders: allSmartFolders, allLabelGroups: allLabelGroups)
            }
            .onChange(of: smartFolderFingerprint) {
                coordinator.ingest(allDocuments: allDocuments, allLabels: allLabels, allSmartFolders: allSmartFolders, allLabelGroups: allLabelGroups)
            }
            .onChange(of: labelGroupFingerprint) {
                coordinator.ingest(allDocuments: allDocuments, allLabels: allLabels, allSmartFolders: allSmartFolders, allLabelGroups: allLabelGroups)
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

#Preview {
    RootView(
        libraryURL: URL(fileURLWithPath: "/tmp/preview.docnestlibrary"),
        librarySession: LibrarySessionController()
    )
    .modelContainer(for: DocumentRecord.self, inMemory: true)
}
