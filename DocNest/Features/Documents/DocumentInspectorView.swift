import SwiftUI
import SwiftData
import PDFKit

struct DocumentInspectorView: View {
    let document: DocumentRecord?

    var body: some View {
        Group {
            if let document {
                VStack(alignment: .leading, spacing: 20) {
                    pdfPreviewSection(for: document)
                        .frame(maxHeight: 360)

                    VStack(alignment: .leading, spacing: 8) {
                        Text(document.title)
                            .font(.title2)
                            .fontWeight(.semibold)

                        Text(document.originalFileName)
                            .foregroundStyle(.secondary)

                        Text("Imported \(document.importedAt.formatted(date: .abbreviated, time: .omitted))")
                            .foregroundStyle(.secondary)

                        Text("\(document.pageCount) pages")
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

    @ViewBuilder
    private func pdfPreviewSection(for document: DocumentRecord) -> some View {
        if let path = document.storedFilePath,
           DocumentStorageService.fileExists(at: path) {
            PDFViewRepresentable(url: DocumentStorageService.fileURL(for: path))
                .clipShape(RoundedRectangle(cornerRadius: 8))
        } else if document.storedFilePath != nil {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.red.opacity(0.08))
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "exclamationmark.triangle")
                            .font(.system(size: 48))
                            .foregroundStyle(.red.opacity(0.6))
                        Text("File not found")
                            .font(.headline)
                        Text("The stored PDF file could not be located.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                }
        } else {
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.secondary.opacity(0.12))
                .overlay {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No PDF file")
                            .font(.headline)
                        Text("Import a PDF to see its preview.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
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
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DocumentRecord.self, configurations: config)

    let labels = LabelTag.makeSamples()
    container.mainContext.insert(labels.finance)
    container.mainContext.insert(labels.tax)

    let doc = DocumentRecord(
        originalFileName: "invoice-march-2026.pdf",
        title: "Invoice March 2026",
        importedAt: .now,
        pageCount: 4,
        labels: [labels.finance, labels.tax]
    )
    container.mainContext.insert(doc)

    return DocumentInspectorView(document: doc)
        .modelContainer(container)
}