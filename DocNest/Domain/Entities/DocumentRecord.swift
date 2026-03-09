import Foundation

struct DocumentRecord: Identifiable, Hashable {
    let id: UUID
    let originalFileName: String
    let title: String
    let importedAt: Date
    let pageCount: Int
    let labels: [LabelTag]
}

extension DocumentRecord {
    static let samples: [DocumentRecord] = [
        DocumentRecord(
            id: UUID(),
            originalFileName: "invoice-march-2026.pdf",
            title: "Invoice March 2026",
            importedAt: .now,
            pageCount: 4,
            labels: [.finance, .tax]
        ),
        DocumentRecord(
            id: UUID(),
            originalFileName: "consulting-contract.pdf",
            title: "Consulting Contract",
            importedAt: .now.addingTimeInterval(-86_400 * 8),
            pageCount: 12,
            labels: [.contracts]
        ),
        DocumentRecord(
            id: UUID(),
            originalFileName: "scan-receipt.pdf",
            title: "Receipt Scan",
            importedAt: .now.addingTimeInterval(-86_400 * 20),
            pageCount: 1,
            labels: []
        )
    ]
}