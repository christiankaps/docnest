import SwiftData
import SwiftUI

enum LabelColor: String, CaseIterable, Identifiable {
    case blue, green, orange, red, teal, indigo, purple, pink, brown, gray

    var id: String { rawValue }

    var displayName: String {
        rawValue.capitalized
    }

    var color: Color {
        switch self {
        case .blue:    .blue
        case .green:   .green
        case .orange:  .orange
        case .red:     .red
        case .teal:    .teal
        case .indigo:  .indigo
        case .purple:  .purple
        case .pink:    .pink
        case .brown:   .brown
        case .gray:    .gray
        }
    }
}

@Model
final class LabelTag {
    var id: UUID
    var name: String
    var unitSymbol: String?
    var colorName: String
    var icon: String?
    var sortOrder: Int
    var groupID: UUID?
    var documents: [DocumentRecord] = []

    init(
        id: UUID = UUID(),
        name: String,
        unitSymbol: String? = nil,
        colorName: String = LabelColor.blue.rawValue,
        sortOrder: Int = 0,
        groupID: UUID? = nil
    ) {
        self.id = id
        self.name = name
        self.unitSymbol = unitSymbol
        self.colorName = colorName
        self.sortOrder = sortOrder
        self.groupID = groupID
    }

    var labelColor: LabelColor {
        get { LabelColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }
}

@Model
final class DocumentLabelValue {
    var id: UUID
    var documentID: UUID
    var labelID: UUID
    var decimalString: String
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        documentID: UUID,
        labelID: UUID,
        decimalString: String,
        updatedAt: Date = .now
    ) {
        self.id = id
        self.documentID = documentID
        self.labelID = labelID
        self.decimalString = decimalString
        self.updatedAt = updatedAt
    }
}

#if DEBUG
extension LabelTag {
    static func makeSamples() -> (finance: LabelTag, tax: LabelTag, contracts: LabelTag) {
        let finance = LabelTag(name: "Finance", colorName: LabelColor.green.rawValue, sortOrder: 0)
        let tax = LabelTag(name: "Tax", colorName: LabelColor.red.rawValue, sortOrder: 1)
        let contracts = LabelTag(name: "Contracts", colorName: LabelColor.indigo.rawValue, sortOrder: 2)
        return (finance, tax, contracts)
    }
}
#endif
