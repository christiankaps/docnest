import SwiftUI
import SwiftData

struct DocumentListView: View {
    let documents: [DocumentRecord]
    @Binding var selectedDocumentIDs: Set<PersistentIdentifier>
    @State private var sortColumn: SortColumn = .importedAt
    @State private var sortDirection: SortDirection = .descending

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
            HStack(spacing: 12) {
                sortButton("Document", column: .title)
                    .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)
                sortButton("Imported", column: .importedAt)
                    .frame(width: 110, alignment: .leading)
                sortButton("Created", column: .createdAt)
                    .frame(width: 110, alignment: .leading)
                sortButton("Pages", column: .pageCount)
                    .frame(width: 60, alignment: .leading)
                sortButton("Size", column: .fileSize)
                    .frame(width: 90, alignment: .leading)
                Text("Labels")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .frame(width: 220, alignment: .leading)
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
                List(sortedDocuments, selection: $selectedDocumentIDs) { document in
                    HStack(alignment: .center, spacing: 12) {
                        HStack(spacing: 10) {
                            RoundedRectangle(cornerRadius: 8)
                                .fill(Color.accentColor.opacity(0.12))
                                .frame(width: 30, height: 30)
                                .overlay {
                                    Image(systemName: "doc.richtext")
                                        .foregroundStyle(.tint)
                                        .font(.system(size: 13, weight: .semibold))
                                }

                            VStack(alignment: .leading, spacing: 3) {
                                Text(document.title)
                                    .font(.system(size: 13, weight: .semibold))
                                    .lineLimit(1)
                            }
                        }
                        .frame(minWidth: 200, maxWidth: .infinity, alignment: .leading)

                        Text(document.importedAt, format: .dateTime.year().month().day())
                            .font(.system(size: 12).monospacedDigit())
                            .frame(width: 110, alignment: .leading)

                        Group {
                            if let sourceCreatedAt = document.sourceCreatedAt {
                                Text(sourceCreatedAt, format: .dateTime.year().month().day())
                            } else {
                                Text("-")
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .font(.system(size: 12).monospacedDigit())
                        .frame(width: 110, alignment: .leading)

                        Text("\(document.pageCount)")
                            .font(.system(size: 12).monospacedDigit())
                            .frame(width: 60, alignment: .leading)

                        Text(document.formattedFileSize)
                            .font(.system(size: 12).monospacedDigit())
                            .frame(width: 90, alignment: .leading)

                        DocumentLabelStrip(labels: document.labels)
                            .frame(width: 220, alignment: .leading)
                    }
                    .padding(.vertical, 4)
                    .tag(document.persistentModelID)
                }
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
                    .font(.caption.weight(.semibold))
                if sortColumn == column {
                    Image(systemName: sortDirection == .ascending ? "arrow.up" : "arrow.down")
                        .font(.caption2.weight(.bold))
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
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        } else {
            HStack(spacing: 6) {
                ForEach(visibleLabels) { label in
                    DocumentListLabelChip(name: label.name)
                }

                if hiddenLabelCount > 0 {
                    Text("+\(hiddenLabelCount)")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
            }
            .lineLimit(1)
        }
    }
}

private struct DocumentListLabelChip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(labelForegroundColor)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(Capsule().fill(labelBackgroundColor))
    }

    private var labelBackgroundColor: Color {
        switch abs(name.hashValue) % 6 {
        case 0:
            Color.blue.opacity(0.16)
        case 1:
            Color.green.opacity(0.16)
        case 2:
            Color.orange.opacity(0.18)
        case 3:
            Color.red.opacity(0.14)
        case 4:
            Color.teal.opacity(0.16)
        default:
            Color.indigo.opacity(0.16)
        }
    }

    private var labelForegroundColor: Color {
        switch abs(name.hashValue) % 6 {
        case 0:
            Color.blue
        case 1:
            Color.green
        case 2:
            Color.orange
        case 3:
            Color.red
        case 4:
            Color.teal
        default:
            Color.indigo
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

    return DocumentListView(
        documents: samples,
        selectedDocumentIDs: .constant(Set(samples.first.map { [$0.persistentModelID] } ?? []))
    )
    .modelContainer(container)
}