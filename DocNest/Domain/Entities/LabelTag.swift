import Foundation
import SwiftData

@Model
final class LabelTag {
    var id: UUID
    var name: String
    var documents: [DocumentRecord] = []

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

extension LabelTag {
    static func makeSamples() -> (finance: LabelTag, tax: LabelTag, contracts: LabelTag) {
        let finance = LabelTag(name: "Finance")
        let tax = LabelTag(name: "Tax")
        let contracts = LabelTag(name: "Contracts")
        return (finance, tax, contracts)
    }
}