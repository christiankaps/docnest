import Foundation
import SwiftData

@Model
final class DocumentRecord {
    var id: UUID
    var originalFileName: String
    var title: String
    var importedAt: Date
    var pageCount: Int

    @Relationship(deleteRule: .nullify, inverse: \LabelTag.documents)
    var labels: [LabelTag] = []

    init(
        id: UUID = UUID(),
        originalFileName: String,
        title: String,
        importedAt: Date,
        pageCount: Int,
        labels: [LabelTag] = []
    ) {
        self.id = id
        self.originalFileName = originalFileName
        self.title = title
        self.importedAt = importedAt
        self.pageCount = pageCount
        self.labels = labels
    }
}

extension DocumentRecord {
    static func makeSamples(labels: (finance: LabelTag, tax: LabelTag, contracts: LabelTag)) -> [DocumentRecord] {
        [
            DocumentRecord(
                originalFileName: "invoice-march-2026.pdf",
                title: "Invoice March 2026",
                importedAt: .now,
                pageCount: 4,
                labels: [labels.finance, labels.tax]
            ),
            DocumentRecord(
                originalFileName: "consulting-contract.pdf",
                title: "Consulting Contract",
                importedAt: .now.addingTimeInterval(-86_400 * 8),
                pageCount: 12,
                labels: [labels.contracts]
            ),
            DocumentRecord(
                originalFileName: "scan-receipt.pdf",
                title: "Receipt Scan",
                importedAt: .now.addingTimeInterval(-86_400 * 20),
                pageCount: 1,
                labels: []
            )
        ]
    }
}