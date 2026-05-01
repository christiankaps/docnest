import AppKit
import SwiftUI
import SwiftData

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
        var value: Bool

        var visibleCount: Int {
            [imported, created, pages, size, labels, value].filter { $0 }.count
        }
    }

    private let documentColumnMinWidth = 260.0
    private let documentColumnCompactMinWidth = 132.0
    private let labelsColumnMinWidth = 110.0
    private let listColumnSpacing = 10.0
    private let listHorizontalPadding = 28.0
    private let listPanelBackground = AppTheme.windowBackground

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
    @AppStorage("docListColumnWidthLabels") private var labelsColumnWidth = 300.0
    @AppStorage("docListColumnWidthValue") private var valueColumnWidth = 120.0
    @AppStorage("docListShowImported") private var showsImportedColumn = true
    @AppStorage("docListShowCreated") private var showsCreatedColumn = true
    @AppStorage("docListShowPages") private var showsPagesColumn = true
    @AppStorage("docListShowSize") private var showsSizeColumn = true
    @AppStorage("docListShowLabels") private var showsLabelsColumn = true
    @AppStorage("docListShowValue") private var showsValueColumn = true

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

    private var effectiveDocumentColumnMinWidth: Double {
        let compactWidth = availableListWidth - listHorizontalPadding - labelsColumnMinWidth - listColumnSpacing
        return max(documentColumnCompactMinWidth, min(documentColumnMinWidth, compactWidth))
    }

    private var effectiveLabelsColumnWidth: Double {
        let availableWidth = availableListWidth - listHorizontalPadding - effectiveDocumentColumnMinWidth - listColumnSpacing
        return max(labelsColumnMinWidth, min(labelsColumnWidth, availableWidth))
    }

    private var effectiveOptionalColumns: OptionalColumnVisibility {
        var visibility = OptionalColumnVisibility(
            imported: showsImportedColumn,
            created: showsCreatedColumn,
            pages: showsPagesColumn,
            size: showsSizeColumn,
            labels: showsLabelsColumn,
            value: showsValueColumn && coordinator.activeLabelValueStatistics != nil
        )
        visibility.labels = true

        let optionalColumnsAvailableWidth = max(
            availableListWidth - listHorizontalPadding - effectiveDocumentColumnMinWidth,
            0
        )

        func requiredOptionalColumnsWidth(for visibility: OptionalColumnVisibility) -> Double {
            var width = 0.0

            if visibility.imported { width += importedColumnWidth }
            if visibility.created { width += createdColumnWidth }
            if visibility.pages { width += pagesColumnWidth }
            if visibility.size { width += sizeColumnWidth }
            if visibility.labels { width += effectiveLabelsColumnWidth }
            if visibility.value { width += valueColumnWidth }

            width += Double(visibility.visibleCount) * listColumnSpacing
            return width
        }

        let hideOrder: [WritableKeyPath<OptionalColumnVisibility, Bool>] = [
            \.pages,
            \.size,
            \.value,
            \.created,
            \.imported,
            \.labels
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
                    : coordinator.activeDocuments.count,
                selectedCount: coordinator.selectedDocumentIDs.count
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
        ContentUnavailableView {
            Label("No Documents", systemImage: "doc.text")
        } description: {
            Text("Import PDFs to populate the library and review them here.")
        } actions: {
            Button {
                coordinator.isImporting = true
            } label: {
                Label("Import PDFs", systemImage: "plus")
            }
            .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppTheme.windowBackground)
        .contextMenu {
            listColumnContextMenuItems
        }
    }

    private var listHeader: some View {
        @Bindable var coordinator = coordinator

        return Group {
            if coordinator.documentListViewMode == .list {
                HStack(spacing: 10) {
                    HStack(spacing: 0) {
                        sortButton("Document", column: .title)
                            .frame(maxWidth: .infinity, alignment: .leading)

                        if DocumentListHeaderLayoutPolicy.showsDocumentLabelsDivider(labelsColumnVisible: effectiveOptionalColumns.labels) {
                            ColumnHeaderDivider()
                        }
                    }
                    .frame(minWidth: effectiveDocumentColumnMinWidth, maxWidth: .infinity, alignment: .leading)

                    if effectiveOptionalColumns.labels {
                        ResizableColumnHeader(width: $labelsColumnWidth, minWidth: labelsColumnMinWidth, displayWidth: effectiveLabelsColumnWidth) {
                            Text("Labels")
                                .font(AppTypography.columnHeader)
                                .lineLimit(1)
                                .foregroundStyle(.secondary)
                        }
                    }

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

                    if effectiveOptionalColumns.value {
                        ResizableColumnHeader(width: $valueColumnWidth, minWidth: 90) {
                            Text("Value")
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
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background {
            Rectangle()
                .fill(AppTheme.headerBackground)
                .overlay(alignment: .bottom) {
                    Rectangle()
                        .fill(AppTheme.separator)
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
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background {
                                    Rectangle()
                                        .fill(AppTheme.headerBackground)
                                        .overlay(alignment: .bottom) {
                                            Rectangle()
                                                .fill(AppTheme.subtleSeparator)
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

        documentRow(
            for: document,
            dragSession: dragSession(for: document),
            onRowTap: {
                handleRowTap(document: document, in: allDocs)
            }
        )
            .padding(.horizontal, 12)
            .background(rowBackground(index: index, isSelected: isSelected))
            .overlay(alignment: .bottom) {
                Rectangle()
                    .fill(AppTheme.subtleSeparator)
                    .frame(height: 0.5)
                    .padding(.leading, 52)
            }
            .contentShape(Rectangle())
            .id(document.persistentModelID)
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
        Toggle("Value", isOn: $showsValueColumn)
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
            return AppTheme.selectedFill
        }
        return index.isMultiple(of: 2) ? Color.clear : Color.primary.opacity(0.015)
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
                            onSelect: {
                                handleRowTap(document: document, in: sortedDocs)
                            },
                            dragSession: dragSession(for: document),
                            labelStates: labelChipStates(for: document),
                            onValueCommit: { label, value in
                                try commitLabelValue(value, for: document, label: label)
                            }
                        )
                        .id(document.persistentModelID)
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
    private func documentRow(
        for document: DocumentRecord,
        dragSession: DocumentDragHelper.DragSession?,
        onRowTap: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .center, spacing: 10) {
            HStack(spacing: 10) {
                RoundedRectangle(cornerRadius: 8)
                    .fill(isSelectedDocument(document) ? Color.accentColor.opacity(0.13) : AppTheme.quietFill)
                    .frame(width: 28, height: 28)
                    .overlay {
                        Image(systemName: "doc.richtext")
                            .foregroundStyle(isSelectedDocument(document) ? Color.accentColor : Color.secondary)
                            .font(.system(size: 14, weight: .medium))
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
            .frame(minWidth: effectiveDocumentColumnMinWidth, maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture(perform: onRowTap)

            if effectiveOptionalColumns.labels {
                ZStack(alignment: .leading) {
                    Color.clear
                        .contentShape(Rectangle())
                        .onTapGesture(perform: onRowTap)

                    DocumentLabelStrip(
                        states: labelChipStates(for: document),
                        isRowSelected: isSelectedDocument(document),
                        onSelect: onRowTap,
                        onRemove: { label in
                            onRemoveLabelFromDocument(label, document)
                        },
                        onValueCommit: { label, value in
                            try commitLabelValue(value, for: document, label: label)
                        }
                    )
                }
                .frame(width: effectiveLabelsColumnWidth, alignment: .leading)
            }

            if effectiveOptionalColumns.imported {
                Text(document.importedAt, format: .dateTime.year().month().day())
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: importedColumnWidth, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onRowTap)
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
                .contentShape(Rectangle())
                .onTapGesture(perform: onRowTap)
            }

            if effectiveOptionalColumns.pages {
                Text("\(document.pageCount)")
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: pagesColumnWidth, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onRowTap)
            }

            if effectiveOptionalColumns.size {
                Text(document.formattedFileSize)
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: sizeColumnWidth, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onRowTap)
            }

            if effectiveOptionalColumns.value {
                let documentValueText = valueText(for: document)
                Text(documentValueText)
                    .font(AppTypography.listMeta.monospacedDigit())
                    .foregroundStyle(documentValueText == "-" ? .secondary : .primary)
                    .frame(width: valueColumnWidth, alignment: .trailing)
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onRowTap)
                    .help("Edit values inline from the matching label chip")
            }

            dragHandle(session: dragSession)

        }
        .padding(.vertical, 7)
    }

    private func dragHandle(session: DocumentDragHelper.DragSession?) -> some View {
        DocumentDragHandleView(session: session)
            .frame(width: 16, height: 20)
    }

    private func isSelectedDocument(_ document: DocumentRecord) -> Bool {
        coordinator.selectedDocumentIDs.contains(document.persistentModelID)
    }

    private func onRemoveLabelFromDocument(_ label: LabelTag, _ document: DocumentRecord) {
        coordinator.toggleLabel(label, on: [document])
    }

    private func labelChipStates(for document: DocumentRecord) -> [DocumentLabelChipState] {
        let activeStatisticsLabelID = coordinator.activeLabelValueStatistics?.labelID
        return document.labels.map { label in
            let rawValue = coordinator.labelValueStringsByDocumentIDAndLabelID[document.id]?[label.id]
            return DocumentLabelChipState(
                label: label,
                valueText: coordinator.formattedLabelValue(for: document.id, label: label),
                rawValue: rawValue,
                isValueEnabled: label.unitSymbol?.isEmpty == false,
                isActiveStatisticsLabel: activeStatisticsLabelID == label.id
            )
        }
    }

    private func commitLabelValue(_ rawValue: String, for document: DocumentRecord, label: LabelTag) throws -> String? {
        if rawValue.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            try ManageLabelValuesUseCase.clearValue(for: document, label: label, using: modelContext)
            coordinator.updateCachedLabelValue(documentID: document.id, labelID: label.id, decimalString: nil)
            return nil
        }

        let normalizedValue = try ManageLabelValuesUseCase.normalizedDecimalString(from: rawValue)
        try ManageLabelValuesUseCase.setValue(rawValue, for: document, label: label, using: modelContext)
        coordinator.updateCachedLabelValue(documentID: document.id, labelID: label.id, decimalString: normalizedValue)
        return normalizedValue
    }

    private func valueText(for document: DocumentRecord) -> String {
        guard let statistics = coordinator.activeLabelValueStatistics else { return "-" }
        guard let valueString = coordinator.activeLabelValueStringsByDocumentID[document.id],
              let decimal = ManageLabelValuesUseCase.decimal(from: valueString) else {
            return "-"
        }
        return ManageLabelValuesUseCase.formattedValue(decimal, unitSymbol: statistics.unitSymbol)
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
            .disabled(coordinator.libraryURL.map { LibraryCoordinator.documentsEligibleForTextExtraction(from: targets, libraryURL: $0).isEmpty } ?? true)

            Button("Re-extract Date") {
                guard let modelContext = coordinator.modelContext else { return }
                coordinator.reExtractDocumentDate(
                    for: DocumentBulkActionSummary.documentsEligibleForDateExtraction(from: targets),
                    modelContext: modelContext
                )
            }
            .disabled(!DocumentBulkActionSummary(documents: targets).canReExtractDates)

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

    private func dragSession(for document: DocumentRecord) -> DocumentDragHelper.DragSession? {
        let draggedDocuments = actionTargetDocuments(for: document)
        let payload = DocumentDragHelper.internalPayload(
            for: document,
            selectedIDs: coordinator.selectedDocumentIDs,
            selectedDocumentIDsToDrag: coordinator.selectedDocumentIDsToDrag
        )
        guard let libraryURL = coordinator.libraryURL else { return nil }
        let exportItems = draggedDocuments.compactMap { dragExportItem(for: $0, libraryURL: libraryURL) }
        guard !exportItems.isEmpty else { return nil }

        return DocumentDragHelper.DragSession(payload: payload, exportItems: exportItems)
    }

    private func dragExportItem(
        for document: DocumentRecord,
        libraryURL: URL
    ) -> ExportDocumentsUseCase.DragExportItem? {
        ExportDocumentsUseCase.unvalidatedDragExportItem(for: document, libraryURL: libraryURL)
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
        var renameResult: DocumentStorageService.StoredFileRenameResult?
        var renameLibraryURL: URL?

        document.title = trimmed

        if let storedFilePath = document.storedFilePath, let libraryURL = coordinator.libraryURL {
            do {
                let result = try DocumentStorageService.renameStoredFile(
                    at: storedFilePath,
                    newTitle: trimmed,
                    contentHash: document.contentHash,
                    libraryURL: libraryURL
                )
                renameResult = result
                renameLibraryURL = libraryURL
                document.storedFilePath = result.updatedPath
            } catch {
                document.title = previousTitle
                document.storedFilePath = previousStoredFilePath
                coordinator.importSummaryMessage = "Could not rename the stored document file: \(error.localizedDescription)"
                renamingDocumentID = nil
                focusedRenameDocumentID = nil
                return
            }
        }

        do {
            try modelContext.save()
            coordinator.recomputeFilteredDocuments()
        } catch {
            if let renameResult, let renameLibraryURL {
                do {
                    try DocumentStorageService.restoreRenamedStoredFile(
                        renameResult,
                        libraryURL: renameLibraryURL
                    )
                    document.title = previousTitle
                    document.storedFilePath = previousStoredFilePath
                } catch {
                    document.storedFilePath = renameResult.updatedPath
                    coordinator.importSummaryMessage = "Could not save the renamed document, and the stored file could not be restored: \(error.localizedDescription)"
                    renamingDocumentID = nil
                    focusedRenameDocumentID = nil
                    return
                }
            } else {
                document.title = previousTitle
                document.storedFilePath = previousStoredFilePath
            }
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
            .padding(.vertical, 2)
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
    var displayWidth: Double?
    @ViewBuilder let content: () -> Content

    @State private var dragStartWidth: Double?
    @State private var cursorState = ResizeHandleCursorState()

    var body: some View {
        HStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .columnHeaderDividerStyle()
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
        .frame(width: displayWidth ?? width, alignment: .leading)
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

struct DocumentListHeaderLayoutPolicy {
    static func showsDocumentLabelsDivider(labelsColumnVisible: Bool) -> Bool {
        labelsColumnVisible
    }
}

private struct ColumnHeaderDivider: View {
    var body: some View {
        Rectangle()
            .columnHeaderDividerStyle()
    }
}

private extension Shape {
    func columnHeaderDividerStyle() -> some View {
        self
            .fill(Color.secondary.opacity(0.35))
            .frame(width: 1, height: 20)
            .padding(.leading, 6)
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

struct InlineLabelValueEditorState: Equatable {
    var isEditing = false
    var draftValue = ""
    var errorMessage: String?

    mutating func beginEditing(rawValue: String?, isValueEnabled: Bool) -> Bool {
        guard isValueEnabled else { return false }
        draftValue = rawValue ?? ""
        errorMessage = nil
        isEditing = true
        return true
    }

    mutating func cancel(rawValue: String?) {
        draftValue = rawValue ?? ""
        errorMessage = nil
        isEditing = false
    }

    func shouldCommitOnFocusChange(isFocused: Bool) -> Bool {
        !isFocused && isEditing
    }

    func hasChanged(from rawValue: String?) -> Bool {
        draftValue.trimmingCharacters(in: .whitespacesAndNewlines) != (rawValue ?? "")
    }

    mutating func finishCommit(normalizedValue: String?) {
        draftValue = normalizedValue ?? ""
        errorMessage = nil
        isEditing = false
    }

    mutating func failCommit(message: String) {
        errorMessage = message
        isEditing = true
    }

    mutating func syncRawValue(_ rawValue: String?) {
        guard !isEditing else { return }
        draftValue = rawValue ?? ""
    }

    mutating func handleValueSupportChange(isValueEnabled: Bool, rawValue: String?) {
        guard !isValueEnabled else { return }
        cancel(rawValue: rawValue)
    }
}

struct DocumentLabelChipState: Identifiable {
    var id: PersistentIdentifier { label.persistentModelID }

    let label: LabelTag
    let valueText: String?
    let rawValue: String?
    let isValueEnabled: Bool
    let isActiveStatisticsLabel: Bool
}

struct DocumentLabelStripDisplayPolicy {
    let states: [DocumentLabelChipState]

    var sortedStates: [DocumentLabelChipState] {
        states.sorted {
            if $0.label.sortOrder == $1.label.sortOrder {
                return $0.label.name.localizedCaseInsensitiveCompare($1.label.name) == .orderedAscending
            }
            return $0.label.sortOrder < $1.label.sortOrder
        }
    }

    var hiddenLabelCount: Int {
        max(states.count - 2, 0)
    }

    func visibleStates(isHovering: Bool, isRowSelected: Bool) -> [DocumentLabelChipState] {
        let sortedStates = sortedStates
        guard sortedStates.count > 2 else { return sortedStates }

        let prioritized = sortedStates.enumerated().sorted { lhs, rhs in
            let lhsPriority = visibilityPriority(for: lhs.element, isHovering: isHovering, isRowSelected: isRowSelected)
            let rhsPriority = visibilityPriority(for: rhs.element, isHovering: isHovering, isRowSelected: isRowSelected)
            if lhsPriority == rhsPriority {
                return lhs.offset < rhs.offset
            }
            return lhsPriority < rhsPriority
        }
        .prefix(2)
        .map(\.element.id)

        let prioritizedIDs = Set(prioritized)
        return sortedStates.filter { prioritizedIDs.contains($0.id) }
    }

    func shouldShowMissingValueAffordance(for state: DocumentLabelChipState, isHovering: Bool, isRowSelected: Bool) -> Bool {
        state.isValueEnabled && state.valueText == nil && (isHovering || isRowSelected)
    }

    func hiddenLabelHelp(isHovering: Bool, isRowSelected: Bool) -> String {
        let visibleIDs = Set(visibleStates(isHovering: isHovering, isRowSelected: isRowSelected).map(\.id))
        let hiddenStates = sortedStates.filter { !visibleIDs.contains($0.id) }
        let missingValueCount = hiddenStates.filter { $0.isValueEnabled && $0.valueText == nil }.count
        if missingValueCount > 0 {
            return "\(hiddenStates.count) hidden labels, \(missingValueCount) missing value\(missingValueCount == 1 ? "" : "s")"
        }
        return "\(hiddenStates.count) hidden labels"
    }

    private func visibilityPriority(for state: DocumentLabelChipState, isHovering: Bool, isRowSelected: Bool) -> Int {
        if state.isActiveStatisticsLabel { return 0 }
        if state.valueText != nil { return 1 }
        if shouldShowMissingValueAffordance(for: state, isHovering: isHovering, isRowSelected: isRowSelected) { return 2 }
        return 3
    }
}

struct DocumentLabelStrip: View {
    let states: [DocumentLabelChipState]
    let isRowSelected: Bool
    let showsEmptyPlaceholder: Bool
    var onSelect: (() -> Void)?
    var onRemove: ((LabelTag) -> Void)?
    var onValueCommit: ((LabelTag, String) throws -> String?)?

    @State private var isHovering = false

    private let displayPolicy: DocumentLabelStripDisplayPolicy

    init(
        states: [DocumentLabelChipState],
        isRowSelected: Bool,
        showsEmptyPlaceholder: Bool = true,
        onSelect: (() -> Void)? = nil,
        onRemove: ((LabelTag) -> Void)? = nil,
        onValueCommit: ((LabelTag, String) throws -> String?)? = nil
    ) {
        self.states = states
        self.isRowSelected = isRowSelected
        self.showsEmptyPlaceholder = showsEmptyPlaceholder
        self.onSelect = onSelect
        self.onRemove = onRemove
        self.onValueCommit = onValueCommit
        self.displayPolicy = DocumentLabelStripDisplayPolicy(states: states)
    }

    var body: some View {
        if displayPolicy.sortedStates.isEmpty {
            if showsEmptyPlaceholder {
                Text("No labels")
                    .font(AppTypography.labelChip)
                    .foregroundStyle(.secondary)
            } else {
                EmptyView()
            }
        } else {
            HStack(spacing: 6) {
                ForEach(visibleStates) { state in
                    RemovableLabelChip(
                        state: state,
                        showsMissingValueAffordance: displayPolicy.shouldShowMissingValueAffordance(
                            for: state,
                            isHovering: isHovering,
                            isRowSelected: isRowSelected
                        ),
                        onSelect: onSelect,
                        onRemove: onRemove,
                        onValueCommit: onValueCommit
                    )
                }

                if displayPolicy.hiddenLabelCount > 0 {
                    Text("+\(displayPolicy.hiddenLabelCount)")
                        .font(AppTypography.labelChip)
                        .foregroundStyle(.secondary)
                        .help(hiddenLabelHelp)
                }
            }
            .lineLimit(1)
            .onHover { hovering in
                withAnimation(.easeInOut(duration: 0.15)) {
                    isHovering = hovering
                }
            }
        }
    }

    private var visibleStates: [DocumentLabelChipState] {
        displayPolicy.visibleStates(isHovering: isHovering, isRowSelected: isRowSelected)
    }

    private var hiddenLabelHelp: String {
        displayPolicy.hiddenLabelHelp(isHovering: isHovering, isRowSelected: isRowSelected)
    }
}

private struct RemovableLabelChip: View {
    let state: DocumentLabelChipState
    let showsMissingValueAffordance: Bool
    var onSelect: (() -> Void)?
    var onRemove: ((LabelTag) -> Void)?
    var onValueCommit: ((LabelTag, String) throws -> String?)?

    @State private var isHovering = false
    @State private var editState = InlineLabelValueEditorState()
    @FocusState private var isValueFieldFocused: Bool

    var body: some View {
        HStack(spacing: 3) {
            if editState.isEditing {
                InlineLabelValueEditorChip(
                    label: state.label,
                    draftValue: Binding(
                        get: { editState.draftValue },
                        set: { editState.draftValue = $0 }
                    ),
                    isFocused: $isValueFieldFocused,
                    hasError: editState.errorMessage != nil,
                    onCommit: commitValue,
                    onCancel: cancelEditing
                )
                .help(editState.errorMessage ?? "Press Return to save value")
            } else {
                LabelChip(
                    name: state.label.name,
                    color: state.label.labelColor,
                    icon: state.label.icon,
                    size: .compact,
                    valueText: state.valueText,
                    showsMissingValueAffordance: showsMissingValueAffordance,
                    showsValueEditIndicator: isHovering && state.valueText != nil,
                    onNameTap: onSelect,
                    onValueTap: state.isValueEnabled ? beginEditing : nil
                )
            }

            if isHovering, onRemove != nil {
                Button {
                    onRemove?(state.label)
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 11))
                        .foregroundStyle(state.label.labelColor.color.opacity(0.7))
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Remove \(state.label.name) label")
                .transition(.opacity)
            }
        }
        .onHover { hovering in
            withAnimation(.easeInOut(duration: 0.15)) {
                isHovering = hovering
            }
        }
        .onChange(of: state.rawValue) { _, newValue in
            editState.syncRawValue(newValue)
        }
        .onChange(of: state.isValueEnabled) { _, isValueEnabled in
            editState.handleValueSupportChange(isValueEnabled: isValueEnabled, rawValue: state.rawValue)
        }
        .onChange(of: isValueFieldFocused) { _, focused in
            guard editState.shouldCommitOnFocusChange(isFocused: focused) else { return }
            commitValue()
        }
    }

    private func beginEditing() {
        guard editState.beginEditing(rawValue: state.rawValue, isValueEnabled: state.isValueEnabled) else { return }
        Task { @MainActor in
            isValueFieldFocused = true
        }
    }

    private func cancelEditing() {
        editState.cancel(rawValue: state.rawValue)
    }

    private func commitValue() {
        guard state.isValueEnabled else {
            cancelEditing()
            return
        }
        guard let onValueCommit else {
            cancelEditing()
            return
        }
        guard editState.hasChanged(from: state.rawValue) else {
            cancelEditing()
            return
        }

        do {
            let normalizedValue = try onValueCommit(state.label, editState.draftValue)
            editState.finishCommit(normalizedValue: normalizedValue)
        } catch {
            editState.failCommit(message: error.localizedDescription)
            isValueFieldFocused = true
        }
    }
}

private struct InlineLabelValueEditorChip: View {
    let label: LabelTag
    @Binding var draftValue: String
    var isFocused: FocusState<Bool>.Binding
    let hasError: Bool
    let onCommit: () -> Void
    let onCancel: () -> Void

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 3) {
                if let icon = label.icon, !icon.isEmpty {
                    Text(icon)
                        .font(AppTypography.labelChip)
                        .accessibilityHidden(true)
                }
                Text(label.name)
                    .font(AppTypography.labelChip)
                    .foregroundStyle(label.labelColor.color)
                    .lineLimit(1)
            }
            .padding(.leading, 8)
            .padding(.trailing, 7)
            .padding(.vertical, 3)

            Rectangle()
                .fill(label.labelColor.color.opacity(0.24))
                .frame(width: 1)
                .padding(.vertical, 4)
                .accessibilityHidden(true)

            TextField("Value", text: $draftValue)
                .textFieldStyle(.plain)
                .font(AppTypography.labelChip.monospacedDigit())
                .frame(width: 64)
                .focused(isFocused)
                .onSubmit(onCommit)
                .onExitCommand(perform: onCancel)
                .padding(.horizontal, 7)
                .padding(.vertical, 3)
                .background(label.labelColor.color.opacity(0.1))
        }
        .background(
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(label.labelColor.color.opacity(0.16))
        )
        .overlay {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .stroke(hasError ? Color.red : Color.clear, lineWidth: 1)
        }
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .accessibilityLabel("Edit \(label.name) value")
    }
}

struct DocumentThumbnailCell: View {
    let document: DocumentRecord
    let libraryURL: URL?
    let size: Double
    let isSelected: Bool
    let isRenaming: Bool
    @Binding var renamingTitle: String
    var onCommitRename: () -> Void
    var onCancelRename: () -> Void
    var onBeginRename: () -> Void
    var onSelect: () -> Void
    let dragSession: DocumentDragHelper.DragSession?
    let labelStates: [DocumentLabelChipState]
    let onValueCommit: ((LabelTag, String) throws -> String?)?

    @Environment(ThumbnailCache.self) private var thumbnailCache
    @FocusState private var isRenameFieldFocused: Bool

    private let badgeLabels: [LabelTag]
    private let badgeOverflowCount: Int

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
        onSelect: @escaping () -> Void = {},
        dragSession: DocumentDragHelper.DragSession?,
        labelStates: [DocumentLabelChipState] = [],
        onValueCommit: ((LabelTag, String) throws -> String?)? = nil
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
        self.onSelect = onSelect
        self.dragSession = dragSession
        self.onValueCommit = onValueCommit

        let sortedLabels = document.labels.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
        self.labelStates = labelStates.isEmpty
            ? sortedLabels.map {
                DocumentLabelChipState(
                    label: $0,
                    valueText: nil,
                    rawValue: nil,
                    isValueEnabled: $0.unitSymbol?.isEmpty == false,
                    isActiveStatisticsLabel: false
                )
            }
            : labelStates
        self.badgeLabels = Array(sortedLabels.prefix(4))
        self.badgeOverflowCount = max(sortedLabels.count - self.badgeLabels.count, 0)
    }

    var body: some View {
        VStack(spacing: 8) {
            thumbnailImage
                .frame(width: size, height: size * 1.3)
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                .overlay(alignment: .bottomTrailing) {
                    if !document.labels.isEmpty {
                        labelBadges
                            .padding(6)
                    }
                }
                .overlay(
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .stroke(
                            isSelected ? AppTheme.selectedStroke : AppTheme.separator,
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
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onSelect)
                    .onTapGesture(count: 2) {
                        guard isSelected else { return }
                        let disallowedModifiers: NSEvent.ModifierFlags = [.command, .shift, .option, .control]
                        guard NSEvent.modifierFlags.intersection(disallowedModifiers).isEmpty else { return }
                        onBeginRename()
                    }
            }

            if DocumentThumbnailCellLayoutPolicy.showsMiniLabelBar(labelCount: document.labels.count, isRenaming: isRenaming) {
                miniLabelBar
                    .frame(width: size)
                    .clipped()
            }

            DocumentDragHandleView(session: dragSession)
                .frame(width: 22, height: 18)
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
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
        ZStack(alignment: .leading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(perform: onSelect)

            DocumentLabelStrip(
                states: labelStates,
                isRowSelected: isSelected,
                showsEmptyPlaceholder: false,
                onSelect: onSelect,
                onValueCommit: onValueCommit
            )
        }
    }

    @ViewBuilder
    private var thumbnailImage: some View {
        if let path = document.storedFilePath,
           let libraryURL {
            let targetSize = CGSize(width: size * 2, height: size * 2.6)
            let _ = thumbnailCache.isObserved(
                storedFilePath: path,
                libraryURL: libraryURL,
                size: targetSize
            )
            if let image = thumbnailCache.thumbnail(for: path, libraryURL: libraryURL, size: targetSize) {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .padding(8)
                    .background(Color(nsColor: .textBackgroundColor))
            } else {
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.thinMaterial)
                    .overlay {
                        ProgressView()
                    }
            }
        } else {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.thinMaterial)
                .overlay {
                    Image(systemName: "doc.richtext")
                        .font(.system(size: size * 0.25))
                        .foregroundStyle(.secondary)
                }
        }
    }
}

enum DocumentThumbnailCellLayoutPolicy {
    static func showsMiniLabelBar(labelCount: Int, isRenaming: Bool) -> Bool {
        !isRenaming && labelCount > 0
    }
}

private struct DocumentListStatusBar: View {
    let filteredCount: Int
    let totalCount: Int
    let selectedCount: Int

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

            if selectedCount > 0 {
                Text(selectionText)
                    .font(AppTypography.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.horizontal, 12)
        .frame(height: 24)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AppTheme.headerBackground)
        .font(AppTypography.caption.monospacedDigit())
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

    private var selectionText: String {
        selectedCount == 1 ? "1 selected" : "\(selectedCount) selected"
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
            let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, DocumentLabelValue.self, configurations: configuration)
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
