import SwiftUI

struct DocumentListView: View {
    let documents: [DocumentRecord]
    @Binding var selectedDocumentID: DocumentRecord.ID?

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
            .tag(document.id)
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
    DocumentListView(
        documents: DocumentRecord.samples,
        selectedDocumentID: .constant(DocumentRecord.samples.first?.id)
    )
}