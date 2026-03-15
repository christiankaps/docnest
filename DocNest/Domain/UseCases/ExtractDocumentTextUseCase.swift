import Foundation
import PDFKit
import SwiftData

enum ExtractDocumentTextUseCase {
    @MainActor
    static func backfillAll(
        documents: [DocumentRecord],
        libraryURL: URL,
        modelContext: ModelContext
    ) async {
        let pending = documents.filter { $0.fullText == nil && $0.storedFilePath != nil }
        guard !pending.isEmpty else { return }

        for document in pending {
            guard let storedFilePath = document.storedFilePath else { continue }
            let fileURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)

            let text = await Task.detached(priority: .utility) {
                ImportPDFDocumentsUseCase.extractText(from: PDFDocument(url: fileURL))
            }.value

            document.fullText = text
        }

        try? modelContext.save()
    }
}
