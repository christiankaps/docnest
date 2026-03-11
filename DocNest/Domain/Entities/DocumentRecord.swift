import Foundation
import SwiftData

@Model
final class DocumentRecord {
    var id: UUID
    var originalFileName: String
    var title: String
    var notes: String
    var sourceCreatedAt: Date?
    var importedAt: Date
    var pageCount: Int
    var fileSize: Int64
    var contentHash: String
    var storedFilePath: String?

    @Relationship(deleteRule: .nullify, inverse: \LabelTag.documents)
    var labels: [LabelTag] = []

    init(
        id: UUID = UUID(),
        originalFileName: String,
        title: String,
        notes: String = "",
        sourceCreatedAt: Date? = nil,
        importedAt: Date,
        pageCount: Int,
        fileSize: Int64 = 0,
        contentHash: String = "",
        storedFilePath: String? = nil,
        labels: [LabelTag] = []
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.title = title
        self.notes = notes
        self.sourceCreatedAt = sourceCreatedAt
        self.importedAt = importedAt
        self.pageCount = pageCount
        self.fileSize = fileSize
        self.contentHash = contentHash
        self.storedFilePath = storedFilePath
        self.labels = labels
    }
}

extension DocumentRecord {
    var formattedFileSize: String {
        ByteCountFormatter.documentFileSize.string(fromByteCount: fileSize)
    }

    func labelSummary(emptyText: String) -> String {
        let labelNames = labels.map(\.name).sorted()
        if labelNames.isEmpty {
            return emptyText
        }

        return labelNames.joined(separator: ", ")
    }

    static func makeSamples(labels: (finance: LabelTag, tax: LabelTag, contracts: LabelTag)) -> [DocumentRecord] {
        [
            DocumentRecord(
                originalFileName: "invoice-march-2026.pdf",
                title: "Invoice March 2026",
                notes: "Quarterly VAT filing reference and payment confirmation.",
                sourceCreatedAt: .now.addingTimeInterval(-86_400 * 2),
                importedAt: .now,
                pageCount: 4,
                fileSize: 182_144,
                contentHash: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                labels: [labels.finance, labels.tax]
            ),
            DocumentRecord(
                originalFileName: "consulting-contract.pdf",
                title: "Consulting Contract",
                notes: "Signed client agreement for annual retainer.",
                sourceCreatedAt: .now.addingTimeInterval(-86_400 * 14),
                importedAt: .now.addingTimeInterval(-86_400 * 8),
                pageCount: 12,
                fileSize: 904_112,
                contentHash: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                labels: [labels.contracts]
            ),
            DocumentRecord(
                originalFileName: "scan-receipt.pdf",
                title: "Receipt Scan",
                sourceCreatedAt: .now.addingTimeInterval(-86_400 * 25),
                importedAt: .now.addingTimeInterval(-86_400 * 20),
                pageCount: 1,
                fileSize: 96_512,
                contentHash: UUID().uuidString.replacingOccurrences(of: "-", with: ""),
                labels: []
            )
        ]
    }
}

private extension ByteCountFormatter {
    static let documentFileSize: ByteCountFormatter = {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter
    }()
}