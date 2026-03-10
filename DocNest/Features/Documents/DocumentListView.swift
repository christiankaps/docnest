import SwiftUI
import SwiftData

struct DocumentListView: View {
    let documents: [DocumentRecord]
    @Binding var selectedDocumentID: PersistentIdentifier?
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
                sortButton("Title", column: .title)
                    .frame(maxWidth: .infinity, alignment: .leading)
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
                    .frame(width: 180, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.secondary.opacity(0.08))

            List(sortedDocuments, selection: $selectedDocumentID) { document in
                HStack(alignment: .center, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(document.title)
                            .font(.headline)
                        Text(document.originalFileName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)

                    Text(document.importedAt, format: .dateTime.year().month().day())
                        .frame(width: 110, alignment: .leading)

                    Group {
                        if let sourceCreatedAt = document.sourceCreatedAt {
                            Text(sourceCreatedAt, format: .dateTime.year().month().day())
                        } else {
                            Text("-")
                                .foregroundStyle(.secondary)
                        }
                    }
                    .frame(width: 110, alignment: .leading)

                    Text("\(document.pageCount)")
                        .frame(width: 60, alignment: .leading)

                    Text(document.formattedFileSize)
                        .frame(width: 90, alignment: .leading)

                    Text(document.labelSummary(emptyText: "No labels"))
                        .foregroundStyle(.secondary)
                        .frame(width: 180, alignment: .leading)
                }
                .padding(.vertical, 4)
                .tag(document.persistentModelID)
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
        selectedDocumentID: .constant(samples.first?.persistentModelID)
    )
    .modelContainer(container)
}