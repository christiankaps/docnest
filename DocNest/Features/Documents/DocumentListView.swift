import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers

enum DocumentLabelDragPayload {
    static let prefix = "docnest-label:"

    static func payload(for labelID: UUID) -> String {
        "\(prefix)\(labelID.uuidString)"
    }

    static func labelID(from payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else {
            return nil
        }

        let rawID = String(payload.dropFirst(prefix.count))
        return UUID(uuidString: rawID)
    }
}

enum DocumentDragHelper {
    /// Builds the internal payload string for dragging documents.
    static func internalPayload(
        for document: DocumentRecord,
        selectedIDs: Set<PersistentIdentifier>,
        selectedDocumentIDsToDrag: [UUID]
    ) -> String {
        let documentIDsToDrag: [UUID]

        if selectedIDs.contains(document.persistentModelID) {
            documentIDsToDrag = selectedDocumentIDsToDrag
        } else {
            documentIDsToDrag = [document.id]
        }

        return DocumentFileDragPayload.payload(for: documentIDsToDrag)
    }
}

enum DocumentFileDragPayload {
    static let prefix = "docnest-documents:"

    static func payload(for documentIDs: [UUID]) -> String {
        let rawIDs = documentIDs.map(\.uuidString).joined(separator: ",")
        return "\(prefix)\(rawIDs)"
    }

    static func documentIDs(from payload: String) -> [UUID]? {
        guard payload.hasPrefix(prefix) else {
            return nil
        }

        let rawIDs = payload.dropFirst(prefix.count).split(separator: ",")
        let documentIDs = rawIDs.compactMap { UUID(uuidString: String($0)) }
        guard !documentIDs.isEmpty else {
            return nil
        }

        return documentIDs
    }
}

enum DocumentListViewMode: String, CaseIterable {
    case list
    case thumbnails
}

struct DocumentListView: View {
    struct ArrowNavigationStep {
        let nextID: PersistentIdentifier
        let selectedIDs: Set<PersistentIdentifier>
    }

    private struct SortSnapshot: Sendable {
        let documentID: UUID
        let title: String
        let importedAt: Date
        let documentDate: Date?
        let pageCount: Int
        let fileSize: Int64
    }

    private struct OptionalColumnVisibility {
        var imported: Bool
        var created: Bool
        var pages: Bool
        var size: Bool
        var labels: Bool

        var visibleCount: Int {
            [imported, created, pages, size, labels].filter { $0 }.count
        }
    }

    private let documentColumnMinWidth = 260.0
    private let listColumnSpacing = 10.0
    private let listHorizontalPadding = 24.0
    private let listPanelBackground = Color(nsColor: .windowBackgroundColor)

    @Environment(LibraryCoordinator.self) private var coordinator
    @Environment(QuickLookCoordinator.self) private var quickLook
    @Environment(\.modelContext) private var modelContext
    @State private var scrollProxy: ScrollViewProxy?
    @State private var selectionAnchor: PersistentIdentifier?
    @State private var renamingDocumentID: PersistentIdentifier?
    @State private var renamingTitle = ""
    @FocusState private var focusedRenameDocumentID: PersistentIdentifier?
    @State private var sortColumn: SortColumn = .importedAt
    @State private var sortDirection: SortDirection = .descending
    @State private var cachedSortedDocuments: [DocumentRecord] = []
    @State private var cachedSortedDocumentIndices: [PersistentIdentifier: Int] = [:]
    @State private var cachedGroupedDocuments: [DocumentGroup] = []
    @State private var pendingSortedDocumentsDebounceTask: Task<Void, Never>?
    @State private var pendingSortedDocumentsTask: Task<Void, Never>?
    @AppStorage("docListGroupMode") private var groupMode: DocumentGroupMode = .none
    @State private var availableListWidth = AppSplitViewLayout.documentListIdealWidth
    @AppStorage("docListThumbnailSize") private var thumbnailSize = 160.0
    @AppStorage("docListColumnWidthImported") private var importedColumnWidth = 120.0
    @AppStorage("docListColumnWidthCreated") private var createdColumnWidth = 120.0
    @AppStorage("docListColumnWidthPages") private var pagesColumnWidth = 72.0
    @AppStorage("docListColumnWidthSize") private var sizeColumnWidth = 96.0
    @AppStorage("docListColumnWidthLabels") private var labelsColumnWidth = 240.0
    @AppStorage("docListShowImported") private var showsImportedColumn = true
    @AppStorage("docListShowCreated") private var showsCreatedColumn = true
    @AppStorage("docListShowPages") private var showsPagesColumn = true
    @AppStorage("docListShowSize") private var showsSizeColumn = true
    @AppStorage("docListShowLabels") private var showsLabelsColumn = true

    private func recomputeSortedDocuments() {
        let column = sortColumn
        let direction = sortDirection
        let snapshots = coordinator.filteredDocuments.map {
            SortSnapshot(
                documentID: $0.id,
                title: $0.title,
                importedAt: $0.importedAt,
                documentDate: $0.documentDate,
                pageCount: $0.pageCount,
                fileSize: $0.fileSize
            )
        }

        pendingSortedDocumentsTask?.cancel()
        pendingSortedDocumentsTask = Task(priority: .userInitiated) {
            let sortedIDs = snapshots.sorted { lhs, rhs in
                let comparison = Self.compare(lhs, rhs, for: column)
                if comparison == .orderedSame {
                    return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
                }

                if direction == .ascending {
                    return comparison == .orderedAscending
                }

                return comparison == .orderedDescending
            }
            .map(\.documentID)

            guard !Task.isCancelled else { return }

            await MainActor.run {
                guard !Task.isCancelled else { return }
                let documentsByID = Dictionary(uniqueKeysWithValues: coordinator.filteredDocuments.map { ($0.id, $0) })
                cachedSortedDocuments = sortedIDs.compactMap { documentsByID[$0] }
                cachedSortedDocumentIndices = Dictionary(
                    uniqueKeysWithValues: cachedSortedDocuments.enumerated().map { ($0.element.persistentModelID, $0.offset) }
                )
                cachedGroupedDocuments = groupMode == .none ? [] : groupMode.group(cachedSortedDocuments)
                pendingSortedDocumentsTask = nil
            }
        }
    }

    private func scheduleSortedDocumentsRecompute() {
        pendingSortedDocumentsDebounceTask?.cancel()
        pendingSortedDocumentsDebounceTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            recomputeSortedDocuments()
            pendingSortedDocumentsDebounceTask = nil
        }
    }

    private var effectiveOptionalColumns: OptionalColumnVisibility {
        var visibility = OptionalColumnVisibility(
            imported: showsImportedColumn,
            created: showsCreatedColumn,
            pages: showsPagesColumn,
            size: showsSizeColumn,
            labels: showsLabelsColumn
        )

        let optionalColumnsAvailableWidth = max(
            availableListWidth - listHorizontalPadding - documentColumnMinWidth,
            0
        )

        func requiredOptionalColumnsWidth(for visibility: OptionalColumnVisibility) -> Double {
            var width = 0.0

            if visibility.imported { width += importedColumnWidth }
            if visibility.created { width += createdColumnWidth }
            if visibility.pages { width += pagesColumnWidth }
            if visibility.size { width += sizeColumnWidth }
            if visibility.labels { width += labelsColumnWidth }

            width += Double(visibility.visibleCount) * listColumnSpacing
            return width
        }

        let hideOrder: [WritableKeyPath<OptionalColumnVisibility, Bool>] = [
            \.labels,
            \.size,
            \.pages,
            \.created,
            \.imported
        ]

        for keyPath in hideOrder where requiredOptionalColumnsWidth(for: visibility) > optionalColumnsAvailableWidth {
            if visibility[keyPath: keyPath] {
                visibility[keyPath: keyPath] = false
            }
        }

        return visibility
    }

    private var visibleDocumentsInOrder: [DocumentRecord] {
        if groupMode == .none {
            return cachedSortedDocuments
        }
        return cachedGroupedDocuments.flatMap(\.documents)
    }

    var body: some View {
        let documents = cachedSortedDocuments
        let visibleDocuments = visibleDocumentsInOrder
        VStack(spacing: 0) {
            if documents.isEmpty || coordinator.documentListViewMode != .list {
                listHeader
            }

            Group {
                if documents.isEmpty {
                    emptyContent
                } else if coordinator.documentListViewMode == .list {
                    listContent(documents)
                } else {
                    thumbnailContent(documents)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider()

            DocumentListStatusBar(
                filteredCount: documents.count,
                totalCount: coordinator.isBinSelected
                    ? coordinator.trashedDocuments.count
                    : coordinator.activeDocuments.count
            )
        }
        .focusable()
        .focusEffectDisabled()
        .background(listPanelBackground)
        .onKeyPress(.space) {
            quickLook.togglePreview()
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { keyPress in
            handleArrowKey(keyPress, in: visibleDocuments)
        }
        .background {
            GeometryReader { proxy in
                Color.clear
                    .onAppear {
                        availableListWidth = proxy.size.width
                    }
                    .onChange(of: proxy.size.width) { _, newWidth in
                        availableListWidth = newWidth
                    }
            }
        }
        .onAppear {
            scheduleSortedDocumentsRecompute()
        }
        .onChange(of: coordinator.filteredDocuments) {
            scheduleSortedDocumentsRecompute()
        }
        .onChange(of: coordinator.filteredDocumentsVersion) {
            scheduleSortedDocumentsRecompute()
        }
        .onChange(of: sortColumn) {
            scheduleSortedDocumentsRecompute()
        }
        .onChange(of: sortDirection) {
            scheduleSortedDocumentsRecompute()
        }
        .onChange(of: groupMode) {
            scheduleSortedDocumentsRecompute()
        }
        .onDisappear {
            pendingSortedDocumentsDebounceTask?.cancel()
            pendingSortedDocumentsTask?.cancel()
            pendingSortedDocumentsDebounceTask = nil
            pendingSortedDocumentsTask = nil
        }
    }

    private var emptyContent: some View {
        ContentUnavailableView(
            "No Documents",
            systemImage: "doc.text",
            description: Text("Import PDFs to populate the library and review them here.")
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(.background)
        .contextMenu {
            listColumnContextMenuItems
        }
    }

    private var listHeader: some View {
        @Bindable var coordinator = coordinator

        return Group {
            if coordinator.documentListViewMode == .list {
                HStack(spacing: 10) {
                    sortButton("Document", column: .title)
                        .frame(minWidth: documentColumnMinWidth, maxWidth: .infinity, alignment: .leading)

                    if effectiveOptionalColumns.imported {
                        ResizableColumnHeader(width: $importedColumnWidth, minWidth: 96) {
                            sortButton("Imported", column: .importedAt)
                        }
                    }

                    if effectiveOptionalColumns.created {
                        ResizableColumnHeader(width: $createdColumnWidth, minWidth: 96) {
                            sortButton("Document Date", column: .documentDate)
                        }
                    }

                    if effectiveOptionalColumns.pages {
                        ResizableColumnHeader(width: $pagesColumnWidth, minWidth: 54) {
                            sortButton("Pages", column: .pageCount)
                        }
                    }

                    if effectiveOptionalColumns.size {
                        ResizableColumnHeader(width: $sizeColumnWidth, minWidth: 72) {
                            sortButton("Size", column: .fileSize)
                        }
                    }

                    if effectiveOptionalColumns.labels {
                        ResizableColumnHeader(width: $labelsColumnWidth, minWidth: 120) {
                            Text("Labels")
                                .font(AppTypography.columnHeader)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            } else {
                HStack(spacing: 10) {
                    sortButton("Document", column: .title)
                    sortButton("Imported", column: .importedAt)
                    sortButton("Document Date", column: .documentDate)
                    sortButton("Size", column: .fileSize)

                    Spacer(minLength: 0)

                    Slider(value: $thumbnailSize, in: 100...320)
                        .frame(width: 120)
                        .help("Thumbnail size")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(Color(nsColor: .windowBackgroundColor))
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(Color.primary.opacity(0.06))
                        .frame(height: 0.5)
                }
        }
    }

    private func listContent(_ sortedDocs: [DocumentRecord]) -> some View {
        let visibleDocs = visibleDocumentsInOrder

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    if groupMode == .none {
                        Section {
                            ForEach(Array(sortedDocs.enumerated()), id: \.element.persistentModelID) { index, document in
                                documentListRow(document: document, index: index, allDocs: visibleDocs)
                            }
                        } header: {
                            listHeader
                        }
                    } else {
                        // Pinned column header as its own section
                        Section {} header: { listHeader }

                        // One pinned section per group
                        ForEach(Array(cachedGroupedDocuments.enumerated()), id: \.element.id) { _, group in
                            Section {
                                ForEach(Array(group.documents.enumerated()), id: \.element.persistentModelID) { index, document in
                                    documentListRow(document: document, index: index, allDocs: visibleDocs)
                                }
                            } header: {
                                HStack {
                                    Text(group.label)
                                        .font(AppTypography.sectionLabel)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("\(group.documents.count)")
                                        .font(AppTypography.caption)
                                        .foregroundStyle(.tertiary)
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    Rectangle()
                                        .fill(Color(nsColor: .windowBackgroundColor))
                                        .overlay(alignment: .bottom) {
                                            Rectangle()
                                                .fill(Color.primary.opacity(0.04))
                                                .frame(height: 0.5)
                                        }
                                }
                            }
                        }
                    }
                }
            }
            .onAppear { scrollProxy = proxy }
        }
        .contextMenu {
            listColumnContextMenuItems
        }
    }

    @ViewBuilder
    private func documentListRow(document: DocumentRecord, index: Int, allDocs: [DocumentRecord]) -> some View {
        let isSelected = coordinator.selectedDocumentIDs.contains(document.persistentModelID)

        documentRow(for: document, dragPayload: dragPayload(for: document))
            .padding(.horizontal, 12)
            .background(rowBackground(index: index, isSelected: isSelected))
            .contentShape(Rectangle())
            .id(document.persistentModelID)
            .highPriorityGesture(TapGesture().onEnded {
                handleRowTap(document: document, in: allDocs)
            })
            .contextMenu { documentContextMenu(for: document) }
            .dropDestination(for: String.self) { items, _ in
                guard let labelID = items.compactMap(DocumentLabelDragPayload.labelID(from:)).first else {
                    return false
                }
                let targets = dropTargetDocuments(for: document)
                return coordinator.assignDroppedLabelToDocuments(labelID, documents: targets)
            }
    }

    @ViewBuilder
    private var listColumnContextMenuItems: some View {
        Text("Visible Attributes")
        Toggle("Imported", isOn: $showsImportedColumn)
        Toggle("Document Date", isOn: $showsCreatedColumn)
        Toggle("Pages", isOn: $showsPagesColumn)
        Toggle("Size", isOn: $showsSizeColumn)
        Toggle("Labels", isOn: $showsLabelsColumn)
        Divider()
        Text("Group By")
        Picker("Group By", selection: $groupMode) {
            Text("None").tag(DocumentGroupMode.none)
            Text("Year").tag(DocumentGroupMode.year)
            Text("Year & Month").tag(DocumentGroupMode.yearMonth)
            Text("Year & Calendar Week").tag(DocumentGroupMode.yearCalendarWeek)
        }
        .pickerStyle(.inline)
        .labelsHidden()
    }

    private func handleRowTap(document: DocumentRecord, in sortedDocs: [DocumentRecord]) {
        coordinator.beginSelectionInteraction()
        let id = document.persistentModelID
        let modifiers = NSEvent.modifierFlags

        if modifiers.contains(.shift), let anchor = selectionAnchor {
            let ids = sortedDocs.map(\.persistentModelID)
            if let anchorIndex = ids.firstIndex(of: anchor),
               let clickIndex = ids.firstIndex(of: id) {
                let range = min(anchorIndex, clickIndex)...max(anchorIndex, clickIndex)
                let rangeIDs = Set(ids[range])
                if modifiers.contains(.command) {
                    coordinator.selectedDocumentIDs.formUnion(rangeIDs)
                } else {
                    coordinator.selectedDocumentIDs = rangeIDs
                }
            }
        } else if modifiers.contains(.command) {
            if coordinator.selectedDocumentIDs.contains(id) {
                coordinator.selectedDocumentIDs.remove(id)
            } else {
                coordinator.selectedDocumentIDs.insert(id)
            }
            selectionAnchor = id
        } else {
            coordinator.selectedDocumentIDs = [id]
            selectionAnchor = id
        }
    }

    private func rowBackground(index: Int, isSelected: Bool) -> Color {
        if isSelected {
            return Color.accentColor.opacity(0.11)
        }
        return index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.012)
    }

    private func thumbnailContent(_ sortedDocs: [DocumentRecord]) -> some View {
        @Bindable var coordinator = coordinator

        return ScrollViewReader { proxy in
            ScrollView {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailSize), spacing: 16)], spacing: 16) {
                    ForEach(sortedDocs, id: \.persistentModelID) { document in
                        DocumentThumbnailCell(
                            document: document,
                            libraryURL: coordinator.libraryURL,
                            size: thumbnailSize,
                            isSelected: coordinator.selectedDocumentIDs.contains(document.persistentModelID),
                            isRenaming: renamingDocumentID == document.persistentModelID,
                            renamingTitle: $renamingTitle,
                            onCommitRename: { commitRename(for: document) },
                            onCancelRename: { cancelRename() },
                            onBeginRename: { beginRename(for: document) },
                            dragPayload: dragPayload(for: document)
                        )
                        .id(document.persistentModelID)
                        .highPriorityGesture(TapGesture().onEnded {
                            handleRowTap(document: document, in: sortedDocs)
                        })
                        .contextMenu { documentContextMenu(for: document) }
                        .accessibilityLabel("\(document.title), PDF document")
                    }
                }
                .padding(16)
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    @ViewBuilder
    private func documentRow(for document: DocumentRecord, dragPayload: String) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelectedDocument(document) ? Color.accentColor.opacity(0.12) : Color.primary.opacity(0.035))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(isSelectedDocument(document) ? Color.accentColor : Color.secondary)
                            .font(AppTypography.listTitle)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    if renamingDocumentID == document.persistentModelID {
                        TextField("Title", text: $renamingTitle)
                            .font(AppTypography.listTitle)
                            .textFieldStyle(.plain)
                            .focused($focusedRenameDocumentID, equals: document.persistentModelID)
                            .onSubmit { commitRename(for: document) }
                            .onExitCommand { cancelRename() }
                    } else {
                        Text(document.title)
                            .font(AppTypography.listTitle)
                            .lineLimit(1)
                            .onTapGesture(count: 2) {
                                guard canBeginRename(for: document) else { return }
                                beginRename(for: document)
                            }
                    }
                }
            }
            .frame(minWidth: documentColumnMinWidth, maxWidth: .infinity, alignment: .leading)

            if effectiveOptionalColumns.imported {
                Text(document.importedAt, format: .dateTime.year().month().day())
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: importedColumnWidth, alignment: .leading)
                    .allowsHitTesting(false)
            }

            if effectiveOptionalColumns.created {
                Group {
                    if let documentDate = document.documentDate {
                        Text(documentDate, format: .dateTime.year().month().day())
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(AppTypography.listMeta.monospacedDigit())
                .frame(width: createdColumnWidth, alignment: .leading)
                .allowsHitTesting(false)
            }

            if effectiveOptionalColumns.pages {
                Text("\(document.pageCount)")
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: pagesColumnWidth, alignment: .leading)
                    .allowsHitTesting(false)
            }

            if effectiveOptionalColumns.size {
                Text(document.formattedFileSize)
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: sizeColumnWidth, alignment: .leading)
                    .allowsHitTesting(false)
            }

            if effectiveOptionalColumns.labels {
                DocumentLabelStrip(labels: document.labels) { label in
                    onRemoveLabelFromDocument(label, document)
                }
                .frame(width: labelsColumnWidth, alignment: .leading)
            }

            dragHandle(payload: dragPayload)

        }
        .padding(.vertical, 6)
    }

    private func dragHandle(payload: String) -> some View {
        Image(systemName: "line.3.horizontal")
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(.tertiary)
            .frame(width: 16, height: 20)
            .contentShape(Rectangle())
            .help("Drag document")
            .draggable(payload)
    }

    private func isSelectedDocument(_ document: DocumentRecord) -> Bool {
        coordinator.selectedDocumentIDs.contains(document.persistentModelID)
    }

    private func onRemoveLabelFromDocument(_ label: LabelTag, _ document: DocumentRecord) {
        coordinator.toggleLabel(label, on: [document])
    }

    private func resolvedStoredFileURL(for document: DocumentRecord) -> URL? {
        guard let path = document.storedFilePath, let libraryURL = coordinator.libraryURL else {
            return nil
        }

        return DocumentStorageService.fileURL(for: path, libraryURL: libraryURL)
    }

    private func actionTargetDocuments(for document: DocumentRecord) -> [DocumentRecord] {
        if coordinator.selectedDocumentIDs.contains(document.persistentModelID) {
            return coordinator.immediateSelectionDocuments
        }
        return [document]
    }

    @ViewBuilder
    private func documentContextMenu(for document: DocumentRecord) -> some View {
        let targets = actionTargetDocuments(for: document)

        if coordinator.isBinSelected {
            Button("Restore") {
                coordinator.restoreDocumentFromBin(document)
            }
        } else {
            if !coordinator.allLabels.isEmpty {
                Menu("Labels") {
                    ForEach(coordinator.allLabels) { label in
                        Button {
                            coordinator.toggleLabel(label, on: targets)
                        } label: {
                            HStack {
                                Text(label.name)
                                if targets.allSatisfy({ doc in doc.labels.contains(where: { $0.persistentModelID == label.persistentModelID }) }) {
                                    Image(systemName: "checkmark")
                                }
                            }
                        }
                    }
                }
            }

            if targets.count == 1 {
                Button("Rename") {
                    beginRename(for: document)
                }
            }

            Divider()

            if let fileURL = originalFileURL(for: document) {
                Button("Open Original") {
                    NSWorkspace.shared.open(fileURL)
                }

                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }
            }

            if targets.contains(where: { $0.storedFilePath != nil }) {
                Button(targets.count == 1 ? "Export\u{2026}" : "Export \(targets.count) Documents\u{2026}") {
                    coordinator.exportDocuments(targets)
                }
            }

            Divider()

            Button("Re-extract Text") {
                guard let libraryURL = coordinator.libraryURL, let modelContext = coordinator.modelContext else { return }
                coordinator.reExtractText(for: targets, libraryURL: libraryURL, modelContext: modelContext)
            }

            Button("Re-extract Date") {
                guard let modelContext = coordinator.modelContext else { return }
                coordinator.reExtractDocumentDate(for: targets, modelContext: modelContext)
            }
            .disabled(targets.allSatisfy { $0.fullText == nil || $0.fullText?.isEmpty == true })

            Divider()

            Button("Move to Bin") {
                coordinator.moveToBin(targets)
            }
        }
    }

    private func originalFileURL(for document: DocumentRecord) -> URL? {
        guard let path = document.storedFilePath, let libraryURL = coordinator.libraryURL,
              DocumentStorageService.fileExists(at: path, libraryURL: libraryURL) else {
            return nil
        }
        return DocumentStorageService.fileURL(for: path, libraryURL: libraryURL)
    }

    private func dropTargetDocuments(for document: DocumentRecord) -> [DocumentRecord] {
        actionTargetDocuments(for: document)
    }

    private func dragPayload(for document: DocumentRecord) -> String {
        DocumentDragHelper.internalPayload(
            for: document,
            selectedIDs: coordinator.selectedDocumentIDs,
            selectedDocumentIDsToDrag: coordinator.selectedDocumentIDsToDrag
        )
    }

    private func handleArrowKey(_ keyPress: KeyPress, in sortedDocs: [DocumentRecord]) -> KeyPress.Result {
        guard !coordinator.isQuickLabelPickerPresented else { return .ignored }
        guard !sortedDocs.isEmpty else { return .ignored }

        guard let step = Self.arrowNavigationStep(
            key: keyPress.key,
            anchor: selectionAnchor,
            selectedDocumentIDs: coordinator.selectedDocumentIDs,
            orderedSelectedDocumentIDs: sortedDocs
                .map(\.persistentModelID)
                .filter { coordinator.selectedDocumentIDs.contains($0) },
            visibleDocuments: sortedDocs,
            extendSelection: keyPress.modifiers.contains(.shift)
        ) else {
            return .ignored
        }

        guard let nextDocument = sortedDocs.first(where: { $0.persistentModelID == step.nextID }) else {
            return .ignored
        }
        coordinator.beginSelectionInteraction()
        coordinator.selectedDocumentIDs = step.selectedIDs
        selectionAnchor = step.nextID
        scrollProxy?.scrollTo(step.nextID, anchor: nil)

        if let url = resolvedStoredFileURL(for: nextDocument) {
            quickLook.previewURLs = [url]
        }
        quickLook.reloadIfVisible()

        return .handled
    }

    private func openQuickLook(for document: DocumentRecord) {
        coordinator.beginSelectionInteraction()
        coordinator.selectedDocumentIDs = [document.persistentModelID]
        if let url = resolvedStoredFileURL(for: document) {
            quickLook.previewURLs = [url]
        }
        quickLook.togglePreview()
    }

    private func beginRename(for document: DocumentRecord) {
        renamingTitle = document.title
        renamingDocumentID = document.persistentModelID
        Task { @MainActor in
            focusedRenameDocumentID = document.persistentModelID
        }
    }

    private func commitRename(for document: DocumentRecord) {
        let trimmed = renamingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelRename()
            return
        }

        let previousTitle = document.title
        let previousStoredFilePath = document.storedFilePath

        document.title = trimmed

        if let storedFilePath = document.storedFilePath, let libraryURL = coordinator.libraryURL {
            document.storedFilePath = DocumentStorageService.renameStoredFile(
                at: storedFilePath,
                newTitle: trimmed,
                contentHash: document.contentHash,
                libraryURL: libraryURL
            )
        }

        do {
            try modelContext.save()
            coordinator.recomputeFilteredDocuments()
        } catch {
            // Roll back to keep database and filesystem consistent
            document.title = previousTitle
            document.storedFilePath = previousStoredFilePath
            coordinator.importSummaryMessage = "Could not save the renamed document: \(error.localizedDescription)"
        }

        renamingDocumentID = nil
        focusedRenameDocumentID = nil
    }

    private func cancelRename() {
        renamingDocumentID = nil
        focusedRenameDocumentID = nil
    }

    private func canBeginRename(for document: DocumentRecord) -> Bool {
        guard renamingDocumentID == nil else { return false }
        guard coordinator.selectedDocumentIDs.count == 1,
              coordinator.selectedDocumentIDs.contains(document.persistentModelID) else { return false }
        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
        return NSEvent.modifierFlags.intersection(disallowedModifiers).isEmpty
    }

    private func sortButton(_ title: String, column: SortColumn) -> some View {
        Button {
            if sortColumn == column {
                sortDirection = sortDirection == .ascending ? .descending : .ascending
            } else {
                sortColumn = column
                sortDirection = column.defaultDirection
            }
        } label: {
            HStack(spacing: 4) {
                Text(title)
                    .font(AppTypography.columnHeader)
                    .lineLimit(1)
                if sortColumn == column {
                    Image(systemName: sortDirection == .ascending ? "arrow.up" : "arrow.down")
                        .font(AppTypography.captionStrong)
                }
            }
            .foregroundStyle(sortColumn == column ? Color.primary : Color.secondary)
        }
        .buttonStyle(.plain)
    }

    private func compare(_ lhs: DocumentRecord, _ rhs: DocumentRecord, for column: SortColumn) -> ComparisonResult {
        switch column {
        case .title:
            lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        case .importedAt:
            lhs.importedAt.compare(rhs.importedAt)
        case .documentDate:
            Self.compareOptionalDates(lhs.documentDate, rhs.documentDate)
        case .pageCount:
            Self.compareIntegers(lhs.pageCount, rhs.pageCount)
        case .fileSize:
            Self.compareIntegers(lhs.fileSize, rhs.fileSize)
        }
    }

    nonisolated private static func compare(_ lhs: SortSnapshot, _ rhs: SortSnapshot, for column: SortColumn) -> ComparisonResult {
        switch column {
        case .title:
            lhs.title.localizedCaseInsensitiveCompare(rhs.title)
        case .importedAt:
            lhs.importedAt.compare(rhs.importedAt)
        case .documentDate:
            compareOptionalDates(lhs.documentDate, rhs.documentDate)
        case .pageCount:
            compareIntegers(lhs.pageCount, rhs.pageCount)
        case .fileSize:
            compareIntegers(lhs.fileSize, rhs.fileSize)
        }
    }

    nonisolated private static func compareOptionalDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
        switch (lhs, rhs) {
        case let (left?, right?):
            return left.compare(right)
        case (nil, nil):
            return .orderedSame
        case (nil, _):
            return .orderedAscending
        case (_, nil):
            return .orderedDescending
        }
    }

    nonisolated private static func compareIntegers<T: BinaryInteger>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }

        if lhs > rhs {
            return .orderedDescending
        }

        return .orderedSame
    }

    static func documentIndicesByPersistentID(for documents: [DocumentRecord]) -> [PersistentIdentifier: Int] {
        Dictionary(uniqueKeysWithValues: documents.enumerated().map { ($0.element.persistentModelID, $0.offset) })
    }

    static func arrowNavigationCurrentIndex(
        anchor: PersistentIdentifier?,
        selectedDocumentIDs: Set<PersistentIdentifier>,
        orderedSelectedDocumentIDs: [PersistentIdentifier],
        visibleDocumentIndices: [PersistentIdentifier: Int]
    ) -> Int? {
        if let anchor, let index = visibleDocumentIndices[anchor] {
            return index
        }

        if let firstOrderedSelected = orderedSelectedDocumentIDs.first(where: { visibleDocumentIndices[$0] != nil }) {
            return visibleDocumentIndices[firstOrderedSelected]
        }

        if let firstSelected = selectedDocumentIDs.first(where: { visibleDocumentIndices[$0] != nil }) {
            return visibleDocumentIndices[firstSelected]
        }

        return nil
    }

    static func arrowNavigationStep(
        key: KeyEquivalent,
        anchor: PersistentIdentifier?,
        selectedDocumentIDs: Set<PersistentIdentifier>,
        orderedSelectedDocumentIDs: [PersistentIdentifier],
        visibleDocuments: [DocumentRecord],
        extendSelection: Bool
    ) -> ArrowNavigationStep? {
        guard !visibleDocuments.isEmpty else { return nil }

        let visibleDocumentIndices = documentIndicesByPersistentID(for: visibleDocuments)
        let currentIndex = arrowNavigationCurrentIndex(
            anchor: anchor,
            selectedDocumentIDs: selectedDocumentIDs,
            orderedSelectedDocumentIDs: orderedSelectedDocumentIDs,
            visibleDocumentIndices: visibleDocumentIndices
        )

        let delta: Int
        switch key {
        case .upArrow, .leftArrow:
            delta = -1
        case .downArrow, .rightArrow:
            delta = 1
        default:
            return nil
        }

        let nextIndex: Int
        if let currentIndex {
            nextIndex = min(max(currentIndex + delta, 0), visibleDocuments.count - 1)
        } else {
            nextIndex = delta > 0 ? 0 : visibleDocuments.count - 1
        }

        let nextID = visibleDocuments[nextIndex].persistentModelID
        let selectedIDs = extendSelection ? selectedDocumentIDs.union([nextID]) : [nextID]
        return ArrowNavigationStep(nextID: nextID, selectedIDs: selectedIDs)
    }
}

private struct ResizableColumnHeader<Content: View>: View {
    @Binding var width: Double
    let minWidth: Double
    @ViewBuilder let content: () -> Content

    @State private var dragStartWidth: Double?
    @State private var cursorState = ResizeHandleCursorState()

    var body: some View {
        HStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 1, height: 20)
                .padding(.leading, 6)
                .contentShape(Rectangle())
                .onHover { isHovering in
                    applyCursorUpdate(cursorState.hoverChanged(isHovering))
                }
                .onDisappear {
                    applyCursorUpdate(cursorState.disappeared())
                }
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            if dragStartWidth == nil {
                                dragStartWidth = width
                            }

                            guard let dragStartWidth else {
                                return
                            }

                            width = max(minWidth, dragStartWidth + value.translation.width)
                        }
                        .onEnded { _ in
                            dragStartWidth = nil
                            applyCursorUpdate(cursorState.dragEnded())
                        }
                )
                .help("Drag to resize column")
        }
        .frame(width: width, alignment: .leading)
    }

    private func applyCursorUpdate(_ update: ResizeHandleCursorUpdate) {
        switch update {
        case .none:
            break
        case .resizeLeftRight:
            NSCursor.resizeLeftRight.set()
        case .arrow:
            NSCursor.arrow.set()
        }
    }
}

private enum SortColumn: Equatable {
    case title
    case importedAt
    case documentDate
    case pageCount
    case fileSize

    var defaultDirection: SortDirection {
        switch self {
        case .title:
            .ascending
        case .importedAt, .documentDate, .pageCount, .fileSize:
            .descending
        }
    }
}

private enum SortDirection {
    case ascending
    case descending
}

private struct DocumentLabelStrip: View {
    let labels: [LabelTag]
    var onRemove: ((LabelTag) -> Void)?

    private let sortedLabels: [LabelTag]
    private let visibleLabels: [LabelTag]
    private let hiddenLabelCount: Int

    init(labels: [LabelTag], onRemove: ((LabelTag) -> Void)? = nil) {
        self.labels = labels
        self.onRemove = onRemove
        self.sortedLabels = labels.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
        self.visibleLabels = Array(self.sortedLabels.prefix(2))
        self.hiddenLabelCount = max(labels.count - self.visibleLabels.count, 0)
    }

    var body: some View {
        if sortedLabels.isEmpty {
            Text("No labels")
                .font(AppTypography.labelChip)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ForEach(visibleLabels) { label in
                    RemovableLabelChip(label: label, onRemove: onRemove)
                }

                if hiddenLabelCount > 0 {
                    Text("+\(hiddenLabelCount)")
                        .font(AppTypography.labelChip)
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
    }
}

private struct RemovableLabelChip: View {
    let label: LabelTag
    var onRemove: ((LabelTag) -> Void)?
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 3) {
            LabelChip(name: label.name, color: label.labelColor, icon: label.icon, size: .compact)

            if isHovering, onRemove != nil {
                Button {
                    onRemove?(label)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(label.labelColor.color.opacity(0.7))
                }
                .buttonStyle(.plain)
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
    }
}

private struct DocumentThumbnailCell: View {
    let document: DocumentRecord
    let libraryURL: URL?
    let size: Double
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renamingTitle: String
    var onCommitRename: () -> Void
    var onCancelRename: () -> Void
    var onBeginRename: () -> Void
    let dragPayload: String

    @Environment(ThumbnailCache.self) private var thumbnailCache
    @FocusState private var isRenameFieldFocused: Bool

    private let badgeLabels: [LabelTag]
    private let badgeOverflowCount: Int
    private let miniBarLabels: [LabelTag]
    private let miniBarOverflowCount: Int

    init(
        document: DocumentRecord,
        libraryURL: URL?,
        size: Double,
        isSelected: Bool,
        isRenaming: Bool,
        renamingTitle: Binding<String>,
        onCommitRename: @escaping () -> Void,
        onCancelRename: @escaping () -> Void,
        onBeginRename: @escaping () -> Void,
        dragPayload: String
    ) {
        self.document = document
        self.libraryURL = libraryURL
        self.size = size
        self.isSelected = isSelected
        self.isRenaming = isRenaming
        self._renamingTitle = renamingTitle
        self.onCommitRename = onCommitRename
        self.onCancelRename = onCancelRename
        self.onBeginRename = onBeginRename
        self.dragPayload = dragPayload

        let sortedLabels = document.labels.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
        self.badgeLabels = Array(sortedLabels.prefix(4))
        self.badgeOverflowCount = max(sortedLabels.count - self.badgeLabels.count, 0)
        self.miniBarLabels = Array(sortedLabels.prefix(2))
        self.miniBarOverflowCount = max(sortedLabels.count - self.miniBarLabels.count, 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            thumbnailImage
                .frame(width: size, height: size * 1.3)
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if !document.labels.isEmpty {
                        labelBadges
                            .padding(6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 10, style: .continuous)
                        .stroke(
                            isSelected ? Color.accentColor.opacity(0.72) : Color.primary.opacity(0.08),
                            lineWidth: isSelected ? 1.5 : 0.8
                        )
                )

            if isRenaming {
                TextField("Title", text: $renamingTitle)
                    .font(AppTypography.labelChip)
                    .textFieldStyle(.plain)
                    .focused($isRenameFieldFocused)
                    .multilineTextAlignment(.center)
                    .frame(width: size)
                    .onSubmit { onCommitRename() }
                    .onExitCommand { onCancelRename() }
                    .onAppear {
                        isRenameFieldFocused = true
                    }
            } else {
                Text(document.title)
                    .font(AppTypography.labelChip)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: size)
                    .onTapGesture(count: 2) {
                        guard isSelected else { return }
                        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
                        guard NSEvent.modifierFlags.intersection(disallowedModifiers).isEmpty else { return }
                        onBeginRename()
                    }
            }

            if !isRenaming, !document.labels.isEmpty {
                miniLabelBar
                    .frame(width: size)
                    .clipped()
            }

            Image(systemName: "line.3.horizontal")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.tertiary)
                .frame(width: 22, height: 18)
                .contentShape(Rectangle())
                .help("Drag document")
                .draggable(dragPayload)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(isSelected ? Color.accentColor.opacity(0.05) : Color.clear)
        )
    }

    private var labelBadges: some View {
        return HStack(spacing: -2) {
            ForEach(badgeLabels) { label in
                Circle()
                    .fill(label.labelColor.color)
                    .frame(width: 10, height: 10)
                    .overlay(Circle().stroke(.white.opacity(0.8), lineWidth: 1))
            }
            if badgeOverflowCount > 0 {
                Text("+\(badgeOverflowCount)")
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.leading, 4)
            }
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
        .background(Capsule().fill(.regularMaterial))
    }

    private var miniLabelBar: some View {
        return HStack(spacing: 4) {
            ForEach(miniBarLabels) { label in
                LabelChip(name: label.name, color: label.labelColor, icon: label.icon, size: .compact)
            }
            if miniBarOverflowCount > 0 {
                Text("+\(miniBarOverflowCount)")
                    .font(AppTypography.labelChip)
                    .foregroundStyle(.secondary)
            }
        }
        .lineLimit(1)
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let path = document.storedFilePath,
           let libraryURL {
            let targetSize = CGSize(width: size * 2, height: size * 2.6)
            let _ = thumbnailCache.isObserved(storedFilePath: path, size: targetSize)
            if let image = thumbnailCache.thumbnail(for: path, libraryURL: libraryURL, size: targetSize) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 10, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        ProgressView()
                    }
            }
        } else {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: size * 0.25))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

private struct DocumentListStatusBar: View {
    let filteredCount: Int
    let totalCount: Int

    private var ratio: Double {
        guard totalCount > 0 else { return 0 }
        return Double(filteredCount) / Double(totalCount)
    }

    private var isFiltered: Bool {
        filteredCount != totalCount
    }

    var body: some View {
        HStack(spacing: 8) {
            Text(summaryText)
                .font(AppTypography.caption)
                .foregroundStyle(.secondary)

            if isFiltered {
                ProgressView(value: ratio)
                    .progressViewStyle(.linear)
                    .frame(width: 80)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 22)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(nsColor: .windowBackgroundColor))
    }

    private var summaryText: String {
        if totalCount == 0 {
            return "No documents"
        } else if isFiltered {
            return "\(filteredCount) of \(totalCount) documents"
        } else {
            return "\(totalCount) documents"
        }
    }
}

#if DEBUG
#Preview {
    return DocumentListView()
        .environment(LibraryCoordinator())
        .environment(ThumbnailCache())
        .modelContainer(PreviewData.documentListContainer)
}
#endif

// MARK: - Document Grouping

struct DocumentGroup: Identifiable {
    let id: String
    let label: String
    let documents: [DocumentRecord]
}

enum DocumentGroupMode: String, CaseIterable {
    case none
    case year
    case yearMonth
    case yearCalendarWeek

    /// Groups the given sorted documents according to the mode.
    /// Each group retains the ordering of the input array.
    func group(_ documents: [DocumentRecord]) -> [DocumentGroup] {
        guard self != .none else { return [] }

        var groups: [(key: String, sortKey: String, docs: [DocumentRecord])] = []
        var index: [String: Int] = [:]

        for document in documents {
            let (label, sortKey) = groupLabel(for: document)
            if let existing = index[label] {
                groups[existing].docs.append(document)
            } else {
                index[label] = groups.count
                groups.append((key: label, sortKey: sortKey, docs: [document]))
            }
        }

        // Sort groups: dated groups descending by sortKey, "No Date" always last.
        let noDateKey = "No Date"
        let sorted = groups.sorted { lhs, rhs in
            if lhs.key == noDateKey { return false }
            if rhs.key == noDateKey { return true }
            return lhs.sortKey > rhs.sortKey
        }

        return sorted.map { DocumentGroup(id: $0.key, label: $0.key, documents: $0.docs) }
    }

    private func groupLabel(for document: DocumentRecord) -> (label: String, sortKey: String) {
        guard let date = document.documentDate else {
            return ("No Date", "")
        }

        let cal = Calendar.current
        let year = cal.component(.year, from: date)

        switch self {
        case .none:
            return ("", "")

        case .year:
            let label = String(year)
            return (label, label)

        case .yearMonth:
            let month = cal.component(.month, from: date)
            let monthName = date.formatted(.dateTime.month(.wide).locale(Locale.current))
            let label = "\(monthName) \(year)"
            let sortKey = String(format: "%04d-%02d", year, month)
            return (label, sortKey)

        case .yearCalendarWeek:
            let week = cal.component(.weekOfYear, from: date)
            let label = String(format: "%d · Week %d", year, week)
            let sortKey = String(format: "%04d-%02d", year, week)
            return (label, sortKey)
        }
    }
}

#if DEBUG
@MainActor
private enum PreviewData {
    static let documentListContainer: ModelContainer = {
        let configuration = ModelConfiguration(isStoredInMemoryOnly: true)
        do {
            let container = try ModelContainer(for: DocumentRecord.self, configurations: configuration)
            let labels = LabelTag.makeSamples()
            container.mainContext.insert(labels.finance)
            container.mainContext.insert(labels.tax)
            container.mainContext.insert(labels.contracts)

            for sample in DocumentRecord.makeSamples(labels: labels) {
                container.mainContext.insert(sample)
            }
            return container
        } catch {
            preconditionFailure("Failed to create DocumentListView preview container: \(error)")
        }
    }()
}
#endif
