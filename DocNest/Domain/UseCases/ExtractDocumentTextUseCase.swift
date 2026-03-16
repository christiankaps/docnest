import Foundation
import OSLog
import PDFKit
import SwiftData

enum ExtractDocumentTextUseCase {
    private static let logger = Logger(subsystem: "com.kaps.docnest", category: "textExtraction")

    @MainActor
    static func backfillAll(
        documents: [DocumentRecord],
        libraryURL: URL,
        modelContext: ModelContext
    ) async {
        let pending = documents.filter { $0.fullText == nil && $0.storedFilePath != nil }
        guard !pending.isEmpty else { return }

        let results = await withTaskGroup(
            of: (Int, String?).self,
            returning: [(Int, String?)].self
        ) { group in
            for (index, document) in pending.enumerated() {
                guard let storedFilePath = document.storedFilePath else { continue }
                let fileURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)
                let title = document.title

                group.addTask {
                    do {
                        guard let pdfDocument = PDFDocument(url: fileURL) else {
                            throw CocoaError(.fileReadCorruptFile)
                        }
                        let text = ImportPDFDocumentsUseCase.extractText(from: pdfDocument)
                        return (index, text)
                    } catch {
                        logger.error("Text extraction failed for '\(title)': \(error.localizedDescription)")
                        return (index, nil)
                    }
                }
            }

            var collected: [(Int, String?)] = []
            for await result in group {
                collected.append(result)
            }
            return collected
        }

        for (index, text) in results {
            pending[index].fullText = text
        }

        try? modelContext.save()
    }
}
