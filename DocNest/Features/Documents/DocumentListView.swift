import SwiftUI
import SwiftData

struct DocumentListView: View {
    let documents: [DocumentRecord]
    @Binding var selectedDocumentIDs: Set<PersistentIdentifier>
    @State private var sortColumn: SortColumn = .importedAt
    @State private var sortDirection: SortDirection = .descending
    @AppStorage("docListColumnWidthDocument") private var documentColumnWidth = 300.0
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
        documents.sorted { lhs, rhs in
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
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                ResizableColumnHeader(width: $documentColumnWidth, minWidth: 220) {
                    sortButton("Document", column: .title)
                }

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

                Spacer(minLength: 0)

                Menu {
                    Text("Visible Attributes")
                    Toggle("Imported", isOn: $showsImportedColumn)
                    Toggle("Created", isOn: $showsCreatedColumn)
                    Toggle("Pages", isOn: $showsPagesColumn)
                    Toggle("Size", isOn: $showsSizeColumn)
                    Toggle("Labels", isOn: $showsLabelsColumn)
                } label: {
                    Image(systemName: "slider.horizontal.3")
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Color.secondary.opacity(0.08))

            if sortedDocuments.isEmpty {
                ContentUnavailableView(
                    "No Documents",
                    systemImage: "doc.text",
                    description: Text("Import PDFs to populate the library and review them here.")
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(Array(sortedDocuments.enumerated()), id: \.element.persistentModelID, selection: $selectedDocumentIDs) { index, document in
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
                        .frame(width: documentColumnWidth, alignment: .leading)

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
                            DocumentLabelStrip(labels: document.labels)
                                .frame(width: labelsColumnWidth, alignment: .leading)
                        }

                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, 4)
                    .tag(document.persistentModelID)
                    .listRowBackground(index.isMultiple(of: 2) ? Color.secondary.opacity(0.05) : Color.clear)
                }
                .listStyle(.plain)
            }
        }
        .navigationTitle("Documents")
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

    var body: some View {
        HStack(spacing: 0) {
            content()
                .frame(maxWidth: .infinity, alignment: .leading)

            Rectangle()
                .fill(Color.secondary.opacity(0.35))
                .frame(width: 1, height: 20)
                .padding(.leading, 6)
                .contentShape(Rectangle())
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
                        }
                )
                .help("Drag to resize column")
        }
        .frame(width: width, alignment: .leading)
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

    private var sortedLabels: [LabelTag] {
        labels.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    private var visibleLabels: [LabelTag] {
        Array(sortedLabels.prefix(2))
    }

    private var hiddenLabelCount: Int {
        max(sortedLabels.count - visibleLabels.count, 0)
    }

    var body: some View {
        if sortedLabels.isEmpty {
            Text("No labels")
                .font(AppTypography.labelChip)
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ForEach(visibleLabels) { label in
                    DocumentListLabelChip(name: label.name, color: label.labelColor)
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

private struct DocumentListLabelChip: View {
    let name: String
    let color: LabelColor

    var body: some View {
        Text(name)
            .font(AppTypography.labelChip)
            .foregroundStyle(color.color)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(color.color.opacity(0.16)))
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

    return DocumentListView(
        documents: samples,
        selectedDocumentIDs: .constant(Set(samples.first.map { [$0.persistentModelID] } ?? []))
    )
    .modelContainer(container)
}