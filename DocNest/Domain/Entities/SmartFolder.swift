import Foundation
import SwiftData

@Model
final class SmartFolder {
    var id: UUID
    var name: String
    var icon: String?
    var labelIDs: [UUID]
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        labelIDs: [UUID] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.labelIDs = labelIDs
        self.sortOrder = sortOrder
    }
}
