import Foundation
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
    var colorName: String
    var documents: [DocumentRecord] = []

    init(id: UUID = UUID(), name: String, colorName: String = LabelColor.blue.rawValue) {
        self.id = id
        self.name = name
        self.colorName = colorName
    }

    var labelColor: LabelColor {
        get { LabelColor(rawValue: colorName) ?? .blue }
        set { colorName = newValue.rawValue }
    }
}

extension LabelTag {
    static func makeSamples() -> (finance: LabelTag, tax: LabelTag, contracts: LabelTag) {
        let finance = LabelTag(name: "Finance", colorName: LabelColor.green.rawValue)
        let tax = LabelTag(name: "Tax", colorName: LabelColor.red.rawValue)
        let contracts = LabelTag(name: "Contracts", colorName: LabelColor.indigo.rawValue)
        return (finance, tax, contracts)
    }
}