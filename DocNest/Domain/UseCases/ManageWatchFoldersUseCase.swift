import Foundation
import SwiftData

enum ManageWatchFoldersUseCase {
    @discardableResult
    static func create(
        named name: String,
        icon: String?,
        folderPath: String,
        libraryURL: URL? = nil,
        isEnabled: Bool = true,
        labelIDs: [UUID],
        using modelContext: ModelContext
    ) throws -> WatchFolder {
        let trimmedName = try normalizedName(from: name)

        guard !folderPath.isEmpty else {
            throw WatchFolderValidationError.emptyPath
        }

        try validate(folderPath: folderPath, libraryURL: libraryURL)

        let descriptor = FetchDescriptor<WatchFolder>(sortBy: [SortDescriptor(\.sortOrder)])
        let existing = try modelContext.fetch(descriptor)
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1

        let folder = WatchFolder(
            name: trimmedName,
            icon: icon?.isEmpty == true ? nil : icon,
            folderPath: folderPath,
            isEnabled: isEnabled,
            labelIDs: labelIDs,
            sortOrder: nextOrder
        )
        modelContext.insert(folder)
        try modelContext.save()
        return folder
    }

    static func update(
        _ folder: WatchFolder,
        name: String,
        icon: String?,
        folderPath: String,
        libraryURL: URL? = nil,
        isEnabled: Bool,
        labelIDs: [UUID],
        using modelContext: ModelContext
    ) throws {
        let trimmedName = try normalizedName(from: name)

        guard !folderPath.isEmpty else {
            throw WatchFolderValidationError.emptyPath
        }

        try validate(folderPath: folderPath, libraryURL: libraryURL)

        folder.name = trimmedName
        folder.icon = icon?.isEmpty == true ? nil : icon
        folder.folderPath = folderPath
        folder.isEnabled = isEnabled
        folder.labelIDs = labelIDs
        try modelContext.save()
    }

    static func setEnabled(
        _ folder: WatchFolder,
        enabled: Bool,
        using modelContext: ModelContext
    ) throws {
        folder.isEnabled = enabled
        try modelContext.save()
    }

    static func delete(_ folder: WatchFolder, using modelContext: ModelContext) throws {
        modelContext.delete(folder)
        try modelContext.save()
    }

    private static func normalizedName(from rawName: String) throws -> String {
        let collapsed = rawName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            throw WatchFolderValidationError.emptyName
        }

        return collapsed
    }

    private static func validate(folderPath: String, libraryURL: URL?) throws {
        guard let libraryURL else { return }

        let watchFolderURL = URL(fileURLWithPath: folderPath, isDirectory: true)
        if DocumentLibraryService.contains(watchFolderURL, inLibrary: libraryURL) {
            throw WatchFolderValidationError.insideLibrary
        }
    }
}

enum WatchFolderValidationError: LocalizedError {
    case emptyName
    case emptyPath
    case insideLibrary

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Watch folders need a name."
        case .emptyPath:
            return "Watch folders need a folder path."
        case .insideLibrary:
            return "The open DocNest library and its subfolders cannot be used as watch folders."
        }
    }
}
