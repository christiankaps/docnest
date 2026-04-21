import Foundation
import SwiftData

@Model
final class DocumentRecord {
    var id: UUID
    var originalFileName: String
    var title: String
    /// The content date of the document (e.g. invoice date, contract date).
    /// Extracted from OCR text during import; falls back to the file creation date.
    /// Renamed from `sourceCreatedAt` in schema V4.
    @Attribute(originalName: "sourceCreatedAt") var documentDate: Date?
    var importedAt: Date
    var pageCount: Int
    var fileSize: Int64
    var contentHash: String
    var storedFilePath: String?
    var fullText: String?
    var ocrCompleted: Bool = false
    var trashedAt: Date?

    @Relationship(deleteRule: .nullify, inverse: \LabelTag.documents)
    var labels: [LabelTag] = []

    init(
        id: UUID = UUID(),
        originalFileName: String,
        title: String,
        documentDate: Date? = nil,
        importedAt: Date,
        pageCount: Int,
        fileSize: Int64 = 0,
        contentHash: String = "",
        storedFilePath: String? = nil,
        trashedAt: Date? = nil,
        labels: [LabelTag] = []
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.title = title
        self.documentDate = documentDate
        self.importedAt = importedAt
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.contentHash = contentHash
        self.storedFilePath = storedFilePath
        self.trashedAt = trashedAt
        self.labels = labels
    }
}

extension DocumentRecord {
    var formattedFileSize: String {
        ByteCountFormatter.documentFileSize.string(fromByteCount: fileSize)
    }
}

#if DEBUG
extension DocumentRecord {
    static func makeSamples(labels: (finance: LabelTag, tax: LabelTag, contracts: LabelTag)) -> [DocumentRecord] {
        [
            DocumentRecord(
                originalFileName: "invoice-march-2026.pdf",
                title: "Invoice March 2026",
                documentDate: .now.addingTimeInterval(-86_400 * 2),
                importedAt: .now,
                pageCount: 4,
                fileSize: 182_144,
                contentHash: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                labels: [labels.finance, labels.tax]
            ),
            DocumentRecord(
                originalFileName: "consulting-contract.pdf",
                title: "Consulting Contract",
                documentDate: .now.addingTimeInterval(-86_400 * 14),
                importedAt: .now.addingTimeInterval(-86_400 * 8),
                pageCount: 12,
                fileSize: 904_112,
                contentHash: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                labels: [labels.contracts]
            ),
            DocumentRecord(
                originalFileName: "scan-receipt.pdf",
                title: "Receipt Scan",
                documentDate: .now.addingTimeInterval(-86_400 * 25),
                importedAt: .now.addingTimeInterval(-86_400 * 20),
                pageCount: 1,
                fileSize: 96_512,
                contentHash: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                labels: []
            )
        ]
    }
}
#endif

private extension ByteCountFormatter {
    static let documentFileSize: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()
}