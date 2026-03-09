import SwiftUI
import SwiftData

struct DocumentListView: View {
    let documents: [DocumentRecord]
    @Binding var selectedDocumentID: PersistentIdentifier?

    var body: some View {
        List(documents, selection: $selectedDocumentID) { document in
            VStack(alignment: .leading, spacing: 6) {
                Text(document.title)
                    .font(.headline)

                Text(document.originalFileName)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                HStack(spacing: 12) {
                    Text(document.importedAt, style: .date)
                    Text("\(document.pageCount) pages")
                    Text(labelSummary(for: document))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .padding(.vertical, 4)
            .tag(document.persistentModelID)
        }
        .navigationTitle("Documents")
    }

    private func labelSummary(for document: DocumentRecord) -> String {
        if document.labels.isEmpty {
            return "No labels"
        }

        return document.labels.map(\.name).joined(separator: ", ")
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
        selectedDocumentID: .constant(samples.first?.id)
    )
    .modelContainer(container)
}