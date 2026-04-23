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
        modelContext: ModelContext,
        onProgress: (@MainActor (_ completed: Int, _ total: Int, _ currentTitle: String) -> Void)? = nil
    ) async {
        let pending = documents.filter { $0.fullText == nil && !$0.ocrCompleted && $0.storedFilePath != nil }
        guard !pending.isEmpty else { return }

        for (index, document) in pending.enumerated() {
            if Task.isCancelled { break }

            guard let storedFilePath = document.storedFilePath else { continue }
            let fileURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)
            let title = document.title

            onProgress?(index, pending.count, title)

            let text: String? = await Task.detached(priority: .utility) {
                guard let pdfDocument = PDFDocument(url: fileURL) else {
                    logger.error("Could not open PDF for '\(title)'")
                    return nil as String?
                }
                return await OCRTextExtractionService.extractText(from: pdfDocument, sourceURL: fileURL)
            }.value

            if Task.isCancelled { break }

            if let text, !text.isEmpty {
                document.fullText = text
            }
            document.ocrCompleted = true
        }

        onProgress?(pending.count, pending.count, "")
        try? modelContext.save()
    }
}
