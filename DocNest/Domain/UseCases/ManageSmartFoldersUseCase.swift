import Foundation
import SwiftData

enum ManageSmartFoldersUseCase {
    @discardableResult
    static func create(
        named name: String,
        icon: String?,
        labelIDs: [UUID],
        using modelContext: ModelContext
    ) throws -> SmartFolder {
        let trimmedName = try normalizedName(from: name)

        let descriptor = FetchDescriptor<SmartFolder>(sortBy: [SortDescriptor(\.sortOrder)])
        let existing = try modelContext.fetch(descriptor)
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1

        let folder = SmartFolder(
            name: trimmedName,
            icon: icon?.isEmpty == true ? nil : icon,
            labelIDs: labelIDs,
            sortOrder: nextOrder
        )
        modelContext.insert(folder)
        try modelContext.save()
        return folder
    }

    static func update(
        _ folder: SmartFolder,
        name: String,
        icon: String?,
        labelIDs: [UUID],
        using modelContext: ModelContext
    ) throws {
        let trimmedName = try normalizedName(from: name)
        folder.name = trimmedName
        folder.icon = icon?.isEmpty == true ? nil : icon
        folder.labelIDs = labelIDs
        try modelContext.save()
    }

    static func delete(_ folder: SmartFolder, using modelContext: ModelContext) throws {
        modelContext.delete(folder)
        try modelContext.save()
    }

    static func reorder(from source: IndexSet, to destination: Int, folders: [SmartFolder], using modelContext: ModelContext) throws {
        var reordered = folders
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, folder) in reordered.enumerated() {
            folder.sortOrder = index
        }
        try modelContext.save()
    }

    private static func normalizedName(from rawName: String) throws -> String {
        try StringNormalization.nonEmptyCollapsedWhitespace(rawName, emptyError: SmartFolderValidationError.emptyName)
    }
}

enum SmartFolderValidationError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Smart folders need a name."
        }
    }
}
