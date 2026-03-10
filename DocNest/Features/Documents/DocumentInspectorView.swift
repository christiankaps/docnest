import AppKit
import SwiftUI
import SwiftData
import PDFKit

struct DocumentInspectorView: View {
    let document: DocumentRecord?
    let libraryURL: URL?

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

                        if let sourceCreatedAt = document.sourceCreatedAt {
                            Text("Created \(sourceCreatedAt.formatted(date: .abbreviated, time: .omitted))")
                                .foregroundStyle(.secondary)
                        }

                        Text("\(document.pageCount) pages")
                            .foregroundStyle(.secondary)

                        Text(Self.fileSizeFormatter.string(fromByteCount: document.fileSize))
                            .foregroundStyle(.secondary)

                        Text("Labels: \(labelsText(for: document))")
                            .foregroundStyle(.secondary)
                    }

                    if !document.contentHash.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Content Hash")
                                .font(.headline)
                            Text(document.contentHash)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                                .textSelection(.enabled)
                        }
                    }

                    HStack(spacing: 12) {
                        Button("Open Original") {
                            openOriginalFile(for: document)
                        }
                        .disabled(originalFileURL(for: document) == nil)

                        Button("Show in Finder") {
                            showOriginalFileInFinder(for: document)
                        }
                        .disabled(originalFileURL(for: document) == nil)

                        if let libraryURL {
                            Button("Show Library") {
                                NSWorkspace.shared.activateFileViewerSelecting([libraryURL])
                            }
                        }
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
           let libraryURL,
           DocumentStorageService.fileExists(at: path, libraryURL: libraryURL) {
            PDFViewRepresentable(url: DocumentStorageService.fileURL(for: path, libraryURL: libraryURL))
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

    private func originalFileURL(for document: DocumentRecord) -> URL? {
        guard let path = document.storedFilePath, let libraryURL else {
            return nil
        }

        let fileURL = DocumentStorageService.fileURL(for: path, libraryURL: libraryURL)
        guard FileManager.default.fileExists(atPath: fileURL.path) else {
            return nil
        }

        return fileURL
    }

    private func openOriginalFile(for document: DocumentRecord) {
        guard let fileURL = originalFileURL(for: document) else {
            return
        }

        NSWorkspace.shared.open(fileURL)
    }

    private func showOriginalFileInFinder(for document: DocumentRecord) {
        guard let fileURL = originalFileURL(for: document) else {
            return
        }

        NSWorkspace.shared.activateFileViewerSelecting([fileURL])
    }

    private static let fileSizeFormatter: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()
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
        sourceCreatedAt: .now.addingTimeInterval(-86_400 * 2),
        importedAt: .now,
        pageCount: 4,
        fileSize: 182_144,
        contentHash: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
        labels: [labels.finance, labels.tax]
    )
    container.mainContext.insert(doc)

    return DocumentInspectorView(document: doc, libraryURL: nil)
        .modelContainer(container)
}