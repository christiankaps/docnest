import Foundation
import SwiftData

@Model
final class WatchFolder {
    var id: UUID
    var name: String
    var icon: String?
    var folderPath: String
    var isEnabled: Bool
    var labelIDs: [UUID]
    var sortOrder: Int

    init(
        id: UUID = UUID(),
        name: String,
        icon: String? = nil,
        folderPath: String,
        isEnabled: Bool = true,
        labelIDs: [UUID] = [],
        sortOrder: Int = 0
    ) {
        self.id = id
        self.name = name
        self.icon = icon
        self.folderPath = folderPath
        self.isEnabled = isEnabled
        self.labelIDs = labelIDs
        self.sortOrder = sortOrder
    }
}
