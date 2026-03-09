import SwiftUI

struct DocumentInspectorView: View {
    let document: DocumentRecord?

    var body: some View {
        Group {
            if let document {
                VStack(alignment: .leading, spacing: 20) {
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.secondary.opacity(0.12))
                        .overlay {
                            VStack(spacing: 12) {
                                Image(systemName: "doc.text.magnifyingglass")
                                    .font(.system(size: 48))
                                    .foregroundStyle(.secondary)
                                Text("PDF preview placeholder")
                                    .font(.headline)
                                Text("PDFKit integration will live in the document detail feature.")
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                            .padding()
                        }
                        .frame(maxHeight: 360)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(document.originalFileName)
                            .foregroundStyle(.secondary)

                        Text("Imported \(document.importedAt.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.secondary)

                        Text("Labels: \(labelsText(for: document))")
                            .foregroundStyle(.secondary)
                    }

                    Spacer()
                }
                .padding(24)
                .navigationTitle("Preview")
            } else {
                ContentUnavailableView(
                    "No Document Selected",
                    systemImage: "doc.text",
                    description: Text("Choose a document from the list to inspect its metadata and preview.")
                )
            }
        }
    }

    private func labelsText(for document: DocumentRecord) -> String {
        if document.labels.isEmpty {
            return "None"
        }

        return document.labels.map(\.name).joined(separator: ", ")
    }
}

#Preview {
    DocumentInspectorView(document: DocumentRecord.samples.first)
}