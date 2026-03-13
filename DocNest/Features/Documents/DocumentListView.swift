import AppKit
import SwiftUI
import SwiftData
import UniformTypeIdentifiers
import PDFKit

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
    @Environment(LibraryCoordinator.self) private var coordinator
    @State private var sortColumn: SortColumn = .importedAt
    @State private var sortDirection: SortDirection = .descending
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

    var body: some View {
        @Bindable var coordinator = coordinator

        VStack(spacing: 0) {
            listHeader

            if sortedDocuments.isEmpty {
                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc.text",
                    description: Text("Import PDFs to populate the library and review them here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if coordinator.documentListViewMode == .list {
                listContent
            } else {
                thumbnailContent
            }
        }
        .navigationTitle("Documents")
    }

    private var listHeader: some View {
        @Bindable var coordinator = coordinator

        return Group {
            if coordinator.documentListViewMode == .list {
                HStack(spacing: 10) {
                    sortButton("Document", column: .title)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    if showsImportedColumn {
                        ResizableColumnHeader(width: $importedColumnWidth, minWidth: 96) {
                            sortButton("Imported", column: .importedAt)
                        }
                    }

                    if showsCreatedColumn {
                        ResizableColumnHeader(width: $createdColumnWidth, minWidth: 96) {
                            sortButton("Created", column: .createdAt)
                        }
                    }

                    if showsPagesColumn {
                        ResizableColumnHeader(width: $pagesColumnWidth, minWidth: 54) {
                            sortButton("Pages", column: .pageCount)
                        }
                    }

                    if showsSizeColumn {
                        ResizableColumnHeader(width: $sizeColumnWidth, minWidth: 72) {
                            sortButton("Size", column: .fileSize)
                        }
                    }

                    if showsLabelsColumn {
                        ResizableColumnHeader(width: $labelsColumnWidth, minWidth: 120) {
                            Text("Labels")
                                .font(AppTypography.columnHeader)
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
        .background(Color.secondary.opacity(0.08))
    }

    private var listContent: some View {
        @Bindable var coordinator = coordinator

        return List(selection: $coordinator.selectedDocumentIDs) {
            ForEach(Array(sortedDocuments.enumerated()), id: \.element.persistentModelID) { index, document in
                documentRow(for: document)
                    .tag(document.persistentModelID)
                    .listRowInsets(EdgeInsets(top: 0, leading: 12, bottom: 0, trailing: 12))
                    .listRowBackground(alternatingRowBackground(for: index))
                    .contextMenu { documentContextMenu(for: document) }
                    .onDrag { dragProvider(for: document) }
                    .dropDestination(for: String.self) { items, _ in
                        guard let labelID = items.compactMap(DocumentLabelDragPayload.labelID(from:)).first else {
                            return false
                        }
                        return coordinator.assignDroppedLabelToDocument(labelID, document: document)
                    }
            }
        }
        .listStyle(.plain)
        .contextMenu {
            Text("Visible Attributes")
            Toggle("Imported", isOn: $showsImportedColumn)
            Toggle("Created", isOn: $showsCreatedColumn)
            Toggle("Pages", isOn: $showsPagesColumn)
            Toggle("Size", isOn: $showsSizeColumn)
            Toggle("Labels", isOn: $showsLabelsColumn)
        }
    }

    private var thumbnailContent: some View {
        @Bindable var coordinator = coordinator

        return ScrollView {
            LazyVGrid(columns: [GridItem(.adaptive(minimum: thumbnailSize), spacing: 16)], spacing: 16) {
                ForEach(sortedDocuments, id: \.persistentModelID) { document in
                    DocumentThumbnailCell(
                        document: document,
                        libraryURL: coordinator.libraryURL,
                        size: thumbnailSize,
                        isSelected: coordinator.selectedDocumentIDs.contains(document.persistentModelID)
                    )
                    .onTapGesture {
                        if NSEvent.modifierFlags.contains(.command) {
                            if coordinator.selectedDocumentIDs.contains(document.persistentModelID) {
                                coordinator.selectedDocumentIDs.remove(document.persistentModelID)
                            } else {
                                coordinator.selectedDocumentIDs.insert(document.persistentModelID)
                            }
                        } else {
                            coordinator.selectedDocumentIDs = [document.persistentModelID]
                        }
                    }
                    .contextMenu { documentContextMenu(for: document) }
                    .onDrag { dragProvider(for: document) }
                }
            }
            .padding(16)
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
                    Text(document.title)
                        .font(AppTypography.listTitle)
                        .lineLimit(1)
                }
            }
            .frame(minWidth: 220, maxWidth: .infinity, alignment: .leading)

            if showsImportedColumn {
                Text(document.importedAt, format: .dateTime.year().month().day())
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: importedColumnWidth, alignment: .leading)
            }

            if showsCreatedColumn {
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

            if showsPagesColumn {
                Text("\(document.pageCount)")
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: pagesColumnWidth, alignment: .leading)
            }

            if showsSizeColumn {
                Text(document.formattedFileSize)
                    .font(AppTypography.listMeta.monospacedDigit())
                    .frame(width: sizeColumnWidth, alignment: .leading)
            }

            if showsLabelsColumn {
                DocumentLabelStrip(labels: document.labels) { label in
                    onRemoveLabelFromDocument(label, document)
                }
                .frame(width: labelsColumnWidth, alignment: .leading)
            }

        }
        .padding(.vertical, 4)
    }

    private func alternatingRowBackground(for index: Int) -> Color {
        if index.isMultiple(of: 2) {
            return .clear
        }

        return Color.secondary.opacity(0.08)
    }

    private func onRemoveLabelFromDocument(_ label: LabelTag, _ document: DocumentRecord) {
        coordinator.toggleLabel(label, on: [document])
    }

    private func contextMenuDocuments(for document: DocumentRecord) -> [DocumentRecord] {
        if coordinator.selectedDocumentIDs.contains(document.persistentModelID) {
            return sortedDocuments.filter { coordinator.selectedDocumentIDs.contains($0.persistentModelID) }
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

            Divider()

            if let fileURL = originalFileURL(for: document) {
                Button("Open Original") {
                    NSWorkspace.shared.open(fileURL)
                }

                Button("Show in Finder") {
                    NSWorkspace.shared.activateFileViewerSelecting([fileURL])
                }

                Divider()
            }

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

    private func dragProvider(for document: DocumentRecord) -> NSItemProvider {
        let documentIDsToDrag: [UUID]

        if coordinator.selectedDocumentIDs.contains(document.persistentModelID) {
            documentIDsToDrag = sortedDocuments
                .filter { coordinator.selectedDocumentIDs.contains($0.persistentModelID) }
                .map(\.id)
        } else {
            documentIDsToDrag = [document.id]
        }

        return NSItemProvider(
            item: DocumentFileDragPayload.payload(for: documentIDsToDrag) as NSString,
            typeIdentifier: UTType.plainText.identifier
        )
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
            LabelChip(name: label.name, color: label.labelColor, size: .compact)

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

            Text(document.title)
                .font(AppTypography.labelChip)
                .lineLimit(2)
                .multilineTextAlignment(.center)
                .frame(width: size)
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
