import Foundation

struct LabelTag: Identifiable, Hashable {
    let id: UUID
    let name: String

    init(id: UUID = UUID(), name: String) {
        self.id = id
        self.name = name
    }
}

extension LabelTag {
    static let finance = LabelTag(name: "Finance")
    static let tax = LabelTag(name: "Tax")
    static let contracts = LabelTag(name: "Contracts")
}