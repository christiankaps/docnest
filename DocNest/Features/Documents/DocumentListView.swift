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

struct DocumentDragItem: Transferable {
    let internalPayload: String
    let fileURL: URL?
    let suggestedName: String?

    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            guard let fileURL = item.fileURL else {
                throw CocoaError(.fileNoSuchFile)
            }
            return SentTransferredFile(fileURL, allowAccessingOriginalFile: true)
        }
        .suggestedFileName { $0.suggestedName ?? "Document.pdf" }

        ProxyRepresentation { item in
            item.internalPayload
        }
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

    @Environment(LibraryCoordinator.self) private var coordinator
    @Environment(QuickLookCoordinator.self) private var quickLook
    @Environment(\.modelContext) private var modelContext
    @State private var scrollProxy: ScrollViewProxy?
    @State private var selectionAnchor: PersistentIdentifier?
    @State private var renamingDocumentID: PersistentIdentifier?
    @State private var renamingTitle = ""
    @State private var sortColumn: SortColumn = .importedAt
    @State private var sortDirection: SortDirection = .descending
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

    private var sortedDocuments: [DocumentRecord] {
        coordinator.filteredDocuments.sorted { lhs, rhs in
            let comparison = compare(lhs, rhs, for: sortColumn)
            if comparison == .orderedSame {
                return lhs.title.localizedCaseInsensitiveCompare(rhs.title) == .orderedAscending
            }

            if sortDirection == .ascending {
                return comparison == .orderedAscending
            }

            return comparison == .orderedDescending
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

    var body: some View {
        let documents = sortedDocuments
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
                totalCount: coordinator.selectedSection == .bin
                    ? coordinator.trashedDocuments.count
                    : coordinator.activeDocuments.count
            )
        }
        .focusable()
        .focusEffectDisabled()
        .onKeyPress(.space) {
            quickLook.togglePreview()
            return .handled
        }
        .onKeyPress(keys: [.upArrow, .downArrow, .leftArrow, .rightArrow]) { keyPress in
            handleArrowKey(keyPress, in: documents)
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
            Text("Visible Attributes")
            Toggle("Imported", isOn: $showsImportedColumn)
            Toggle("Created", isOn: $showsCreatedColumn)
            Toggle("Pages", isOn: $showsPagesColumn)
            Toggle("Size", isOn: $showsSizeColumn)
            Toggle("Labels", isOn: $showsLabelsColumn)
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
                            sortButton("Created", column: .createdAt)
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
                    sortButton("Created", column: .createdAt)
                    sortButton("Size", column: .fileSize)

                    Spacer(minLength: 0)

                    Slider(value: $thumbnailSize, in: 100...320)
                        .frame(width: 120)
                        .help("Thumbnail size")
                }
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background {
            Color(nsColor: .windowBackgroundColor)
                .overlay(Color.secondary.opacity(0.08))
        }
    }

    private func listContent(_ sortedDocs: [DocumentRecord]) -> some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                    Section {
                    ForEach(Array(sortedDocs.enumerated()), id: \.element.persistentModelID) { index, document in
                        let isSelected = coordinator.selectedDocumentIDs.contains(document.persistentModelID)

                        documentRow(for: document)
                            .padding(.horizontal, 12)
                            .background(rowBackground(index: index, isSelected: isSelected))
                            .contentShape(Rectangle())
                            .id(document.persistentModelID)
                            .onTapGesture(count: 2) {
                                openQuickLook(for: document)
                            }
                            .onTapGesture {
                                handleRowTap(document: document, in: sortedDocs)
                            }
                            .contextMenu { documentContextMenu(for: document) }
                            .draggable(dragItem(for: document))
                            .dropDestination(for: String.self) { items, _ in
                                guard let labelID = items.compactMap(DocumentLabelDragPayload.labelID(from:)).first else {
                                    return false
                                }
                                let targets = dropTargetDocuments(for: document)
                                return coordinator.assignDroppedLabelToDocuments(labelID, documents: targets)
                            }
                    }
                    } header: {
                        listHeader
                    }
                }
            }
            .onAppear { scrollProxy = proxy }
        }
        .contextMenu {
            Text("Visible Attributes")
            Toggle("Imported", isOn: $showsImportedColumn)
            Toggle("Created", isOn: $showsCreatedColumn)
            Toggle("Pages", isOn: $showsPagesColumn)
            Toggle("Size", isOn: $showsSizeColumn)
            Toggle("Labels", isOn: $showsLabelsColumn)
        }
    }

    private func handleRowTap(document: DocumentRecord, in sortedDocs: [DocumentRecord]) {
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
            return Color.accentColor.opacity(0.18)
        }
        return index.isMultiple(of: 2) ? Color.clear : Color.secondary.opacity(0.06)
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
                            onCancelRename: { cancelRename() }
                        )
                        .id(document.persistentModelID)
                        .onTapGesture(count: 2) {
                            openQuickLook(for: document)
                        }
                        .onTapGesture {
                            handleRowTap(document: document, in: sortedDocs)
                        }
                        .contextMenu { documentContextMenu(for: document) }
                        .draggable(dragItem(for: document))
                        .accessibilityLabel("\(document.title), PDF document")
                    }
                }
                .padding(16)
            }
            .onAppear { scrollProxy = proxy }
        }
    }

    @ViewBuilder
    private func documentRow(for document: DocumentRecord) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.accentColor.opacity(0.12))
                    .frame(width: 30, height: 30)
                    .overlay {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(.tint)
                            .font(AppTypography.listTitle)
                    }

                VStack(alignment: .leading, spacing: 3) {
                    if renamingDocumentID == document.persistentModelID {
                        TextField("Title", text: $renamingTitle)
                            .font(AppTypography.listTitle)
                            .textFieldStyle(.plain)
                            .onSubmit { commitRename(for: document) }
                            .onExitCommand { cancelRename() }
                    } else {
                        Text(document.title)
                            .font(AppTypography.listTitle)
                            .lineLimit(1)
                    }
                }
            }
            .frame(minWidth: documentColumnMinWidth, maxWidth: .infinity, alignment: .leading)

            if effectiveOptionalColumns.imported {
                Text(document.importedAt, format: .dateTime.year().month().day())
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: importedColumnWidth, alignment: .leading)
            }

            if effectiveOptionalColumns.created {
                Group {
                    if let sourceCreatedAt = document.sourceCreatedAt {
                        Text(sourceCreatedAt, format: .dateTime.year().month().day())
                    } else {
                        Text("-")
                            .foregroundStyle(.secondary)
                    }
                }
                .font(AppTypography.listMeta.monospacedDigit())
                .frame(width: createdColumnWidth, alignment: .leading)
            }

            if effectiveOptionalColumns.pages {
                Text("\(document.pageCount)")
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: pagesColumnWidth, alignment: .leading)
            }

            if effectiveOptionalColumns.size {
                Text(document.formattedFileSize)
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: sizeColumnWidth, alignment: .leading)
            }

            if effectiveOptionalColumns.labels {
                DocumentLabelStrip(labels: document.labels) { label in
                    onRemoveLabelFromDocument(label, document)
                }
                .frame(width: labelsColumnWidth, alignment: .leading)
            }

        }
        .padding(.vertical, 4)
    }

    private func onRemoveLabelFromDocument(_ label: LabelTag, _ document: DocumentRecord) {
        coordinator.toggleLabel(label, on: [document])
    }

    private func contextMenuDocuments(for document: DocumentRecord) -> [DocumentRecord] {
        if coordinator.selectedDocumentIDs.contains(document.persistentModelID) {
            return coordinator.filteredDocuments.filter { coordinator.selectedDocumentIDs.contains($0.persistentModelID) }
        }
        return [document]
    }

    @ViewBuilder
    private func documentContextMenu(for document: DocumentRecord) -> some View {
        let targets = contextMenuDocuments(for: document)

        if coordinator.selectedSection == .bin {
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
        if coordinator.selectedDocumentIDs.contains(document.persistentModelID) {
            return coordinator.filteredDocuments.filter {
                coordinator.selectedDocumentIDs.contains($0.persistentModelID)
            }
        }
        return [document]
    }

    private func dragItem(for document: DocumentRecord) -> DocumentDragItem {
        let documentIDsToDrag: [UUID]

        if coordinator.selectedDocumentIDs.contains(document.persistentModelID) {
            documentIDsToDrag = coordinator.filteredDocuments
                .filter { coordinator.selectedDocumentIDs.contains($0.persistentModelID) }
                .map(\.id)
        } else {
            documentIDsToDrag = [document.id]
        }

        let internalPayload = DocumentFileDragPayload.payload(for: documentIDsToDrag)
        let fileURL = originalFileURL(for: document)
        let suggestedName = ExportDocumentsUseCase.suggestedFileName(for: document)

        return DocumentDragItem(
            internalPayload: internalPayload,
            fileURL: fileURL,
            suggestedName: suggestedName
        )
    }

    private func handleArrowKey(_ keyPress: KeyPress, in sortedDocs: [DocumentRecord]) -> KeyPress.Result {
        guard !sortedDocs.isEmpty else { return .ignored }

        let ids = sortedDocs.map(\.persistentModelID)

        // Find the current index based on the last selected document.
        let currentIndex: Int? = if let last = coordinator.selectedDocumentIDs.first(where: { id in ids.contains(id) }) {
            ids.firstIndex(of: last)
        } else {
            nil
        }

        let delta: Int
        switch keyPress.key {
        case .upArrow, .leftArrow:
            delta = -1
        case .downArrow, .rightArrow:
            delta = 1
        default:
            return .ignored
        }

        let nextIndex: Int
        if let currentIndex {
            nextIndex = min(max(currentIndex + delta, 0), ids.count - 1)
        } else {
            nextIndex = delta > 0 ? 0 : ids.count - 1
        }

        let nextID = ids[nextIndex]
        coordinator.selectedDocumentIDs = [nextID]
        selectionAnchor = nextID
        scrollProxy?.scrollTo(nextID, anchor: nil)

        let nextDocument = sortedDocs[nextIndex]
        if let url = originalFileURL(for: nextDocument) {
            quickLook.previewURLs = [url]
        }
        quickLook.reloadIfVisible()

        return .handled
    }

    private func openQuickLook(for document: DocumentRecord) {
        coordinator.selectedDocumentIDs = [document.persistentModelID]
        if let url = originalFileURL(for: document) {
            quickLook.previewURLs = [url]
        }
        quickLook.togglePreview()
    }

    private func beginRename(for document: DocumentRecord) {
        renamingTitle = document.title
        renamingDocumentID = document.persistentModelID
    }

    private func commitRename(for document: DocumentRecord) {
        let trimmed = renamingTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            cancelRename()
            return
        }
        document.title = trimmed

        if let storedFilePath = document.storedFilePath, let libraryURL = coordinator.libraryURL {
            document.storedFilePath = DocumentStorageService.renameStoredFile(
                at: storedFilePath,
                newTitle: trimmed,
                contentHash: document.contentHash,
                libraryURL: libraryURL
            )
        }

        try? modelContext.save()
        renamingDocumentID = nil
    }

    private func cancelRename() {
        renamingDocumentID = nil
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
        case .createdAt:
            compareOptionalDates(lhs.sourceCreatedAt, rhs.sourceCreatedAt)
        case .pageCount:
            compareIntegers(lhs.pageCount, rhs.pageCount)
        case .fileSize:
            compareIntegers(lhs.fileSize, rhs.fileSize)
        }
    }

    private func compareOptionalDates(_ lhs: Date?, _ rhs: Date?) -> ComparisonResult {
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

    private func compareIntegers<T: BinaryInteger>(_ lhs: T, _ rhs: T) -> ComparisonResult {
        if lhs < rhs {
            return .orderedAscending
        }

        if lhs > rhs {
            return .orderedDescending
        }

        return .orderedSame
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
    case createdAt
    case pageCount
    case fileSize

    var defaultDirection: SortDirection {
        switch self {
        case .title:
            .ascending
        case .importedAt, .createdAt, .pageCount, .fileSize:
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

    private var sortedLabels: [LabelTag] {
        labels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var visibleLabels: [LabelTag] {
        Array(sortedLabels.prefix(2))
    }

    private var hiddenLabelCount: Int {
        max(sortedLabels.count - visibleLabels.count, 0)
    }

    init(labels: [LabelTag], onRemove: ((LabelTag) -> Void)? = nil) {
        self.labels = labels
        self.onRemove = onRemove
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

    @Environment(ThumbnailCache.self) private var thumbnailCache

    var body: some View {
        VStack(spacing: 6) {
            thumbnailImage
                .frame(width: size, height: size * 1.3)
                .clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.2), lineWidth: isSelected ? 2 : 1)
                )

            if isRenaming {
                TextField("Title", text: $renamingTitle)
                    .font(AppTypography.labelChip)
                    .textFieldStyle(.plain)
                    .multilineTextAlignment(.center)
                    .frame(width: size)
                    .onSubmit { onCommitRename() }
                    .onExitCommand { onCancelRename() }
            } else {
                Text(document.title)
                    .font(AppTypography.labelChip)
                    .lineLimit(2)
                    .multilineTextAlignment(.center)
                    .frame(width: size)
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(isSelected ? Color.accentColor.opacity(0.12) : Color.clear)
        )
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let path = document.storedFilePath,
           let libraryURL {
            let targetSize = CGSize(width: size * 2, height: size * 2.6)
            if let image = thumbnailCache.thumbnail(for: path, libraryURL: libraryURL, size: targetSize) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
            } else {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color.secondary.opacity(0.08))
                    .overlay {
                        ProgressView()
                    }
            }
        } else {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color.secondary.opacity(0.08))
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
        .frame(height: 24)
        .frame(maxWidth: .infinity, alignment: .leading)
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

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DocumentRecord.self, configurations: config)

    let labels = LabelTag.makeSamples()
    container.mainContext.insert(labels.finance)
    container.mainContext.insert(labels.tax)
    container.mainContext.insert(labels.contracts)

    let samples = DocumentRecord.makeSamples(labels: labels)
    for sample in samples {
        container.mainContext.insert(sample)
    }

    return DocumentListView()
        .environment(LibraryCoordinator())
        .environment(ThumbnailCache())
        .modelContainer(container)
}
