import Foundation

/// Stable identities survive both translation and user renaming.
enum StarterLabel: String, Codable, CaseIterable, Sendable {
    case invoices, banking, insurance, taxes, health, home, work, vehicles, contracts, receipts

    var id: UUID {
        let suffix = switch self {
        case .invoices: "000000000001"
        case .banking: "000000000002"
        case .insurance: "000000000003"
        case .taxes: "000000000004"
        case .health: "000000000005"
        case .home: "000000000006"
        case .work: "000000000007"
        case .vehicles: "000000000008"
        case .contracts: "000000000009"
        case .receipts: "000000000010"
        }
        return UUID(uuidString: "D0C00000-0000-4000-8000-" + suffix)!
    }

    var name: String {
        switch self {
        case .invoices: String(localized: "Invoices")
        case .banking: String(localized: "Banking")
        case .insurance: String(localized: "Insurance")
        case .taxes: String(localized: "Taxes")
        case .health: String(localized: "Health")
        case .home: String(localized: "Home")
        case .work: String(localized: "Work")
        case .vehicles: String(localized: "Vehicles")
        case .contracts: String(localized: "Contracts")
        case .receipts: String(localized: "Receipts")
        }
    }
}

struct LibraryLabel: Codable, Identifiable, Hashable, Sendable {
    let id: UUID
    let starter: StarterLabel?
    var customName: String?
    var name: String { customName ?? starter?.name ?? "" }
}

struct DocumentOrganization: Codable, Sendable {
    var labelIDs: Set<UUID> = []
    var manualDate: DocumentDate?
    var filename: String?
    var deletedAt: Date?
    var reviewState: LibraryDocument.ReviewState = .inbox
}

/// One atomic snapshot keeps label deletion and all its assignments consistent.
struct LibraryOrganization: Codable, Sendable {
    var schemaVersion = 2
    var purgedIDs: Set<UUID>?
    var labels: [LibraryLabel] = StarterLabel.allCases.map { LibraryLabel(id: $0.id, starter: $0, customName: nil) }
    var documents: [String: DocumentOrganization] = [:]

    func applying(to document: LibraryDocument) -> LibraryDocument {
        guard let edit = documents[document.id.uuidString] else { return document }
        var result = document
        result.labelIDs = edit.labelIDs
        result.filename = edit.filename ?? document.filename
        result.deletedAt = edit.deletedAt
        result.reviewState = edit.reviewState
        if let date = edit.manualDate { result.documentDate = date; result.dateSource = .manual }
        return result
    }
}

struct LibraryFilter: Hashable {
    var labelIDs: Set<UUID> = []
    var year: Int?

    func includes(_ document: LibraryDocument) -> Bool {
        labelIDs.isSubset(of: document.labelIDs) && (year == nil || document.documentDate.year == year)
    }
}
