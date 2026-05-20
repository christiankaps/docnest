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
        try StringNormalization.nonEmptyCollapsedWhitespace(rawName, emptyError: WatchFolderValidationError.emptyName)
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

enum ManageDocumentLocationsUseCase {
    @discardableResult
    static func create(named name: String, using modelContext: ModelContext) throws -> DocumentLocation {
        let trimmedName = try normalizedName(from: name)
        let descriptor = FetchDescriptor<DocumentLocation>(sortBy: [SortDescriptor(\.sortOrder)])
        let existing = try modelContext.fetch(descriptor)
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let location = DocumentLocation(name: trimmedName, sortOrder: nextOrder)
        modelContext.insert(location)
        try modelContext.save()
        return location
    }

    static func rename(_ location: DocumentLocation, to name: String, using modelContext: ModelContext) throws {
        location.name = try normalizedName(from: name)
        try modelContext.save()
    }

    static func delete(_ location: DocumentLocation, libraryURL: URL?, using modelContext: ModelContext) throws {
        let coverPhotoPath = location.coverPhotoPath
        let locationID = location.id
        let documents = try modelContext.fetch(FetchDescriptor<DocumentRecord>(
            predicate: #Predicate { document in
                document.physicalLocationID == locationID
            }
        ))
        for document in documents {
            document.availability = .unknown
        }
        modelContext.delete(location)
        try modelContext.save()
        if let libraryURL, let coverPhotoPath {
            removeManagedPhoto(at: coverPhotoPath, libraryURL: libraryURL)
        }
    }

    static func reorder(from source: IndexSet, to destination: Int, locations: [DocumentLocation], using modelContext: ModelContext) throws {
        var reordered = locations
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, location) in reordered.enumerated() {
            location.sortOrder = index
        }
        try modelContext.save()
    }

    static func setAvailability(_ availability: DocumentAvailability, for documents: [DocumentRecord], using modelContext: ModelContext) throws {
        for document in documents {
            document.availability = availability
        }
        try modelContext.save()
    }

    static func assign(_ location: DocumentLocation, to documents: [DocumentRecord], using modelContext: ModelContext) throws {
        for document in documents {
            document.availability = .physical
            document.physicalLocationID = location.id
        }
        try modelContext.save()
    }

    static func documentCount(for location: DocumentLocation, using modelContext: ModelContext) throws -> Int {
        let locationID = location.id
        return try modelContext.fetchCount(FetchDescriptor<DocumentRecord>(
            predicate: #Predicate { document in
                document.physicalLocationID == locationID
            }
        ))
    }

    static func setCoverPhoto(from sourceURL: URL, for location: DocumentLocation, libraryURL: URL, using modelContext: ModelContext) throws {
        let fileExtension = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension
        let relativePath = DocumentLibraryService.relativeLocationPhotoPath(for: location.id, fileExtension: fileExtension)
        let destinationURL = DocumentLibraryService.locationPhotoURL(for: relativePath, libraryURL: libraryURL)
        let sourceURL = sourceURL.standardizedFileURL
        let fileManager = FileManager.default
        try FileManager.default.createDirectory(at: destinationURL.deletingLastPathComponent(), withIntermediateDirectories: true)

        let oldPath = location.coverPhotoPath
        let temporaryURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(location.id.uuidString)-\(UUID().uuidString).tmp")
            .appendingPathExtension(destinationURL.pathExtension)
        let backupURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(location.id.uuidString)-\(UUID().uuidString).backup")
            .appendingPathExtension(destinationURL.pathExtension)

        try fileManager.copyItem(at: sourceURL, to: temporaryURL)
        let hadExistingDestination = fileManager.fileExists(atPath: destinationURL.path)
        do {
            if hadExistingDestination {
                try fileManager.moveItem(at: destinationURL, to: backupURL)
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            } else {
                try fileManager.moveItem(at: temporaryURL, to: destinationURL)
            }
        } catch {
            try? fileManager.removeItem(at: temporaryURL)
            if fileManager.fileExists(atPath: backupURL.path) && !fileManager.fileExists(atPath: destinationURL.path) {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }
            throw error
        }

        location.coverPhotoPath = relativePath

        do {
            try modelContext.save()
        } catch {
            try? fileManager.removeItem(at: destinationURL)
            if hadExistingDestination {
                try? fileManager.moveItem(at: backupURL, to: destinationURL)
            }
            location.coverPhotoPath = oldPath
            throw error
        }

        try? fileManager.removeItem(at: backupURL)
        if let oldPath, oldPath != relativePath {
            removeManagedPhoto(at: oldPath, libraryURL: libraryURL)
        }
    }

    static func removeCoverPhoto(for location: DocumentLocation, libraryURL: URL, using modelContext: ModelContext) throws {
        let oldPath = location.coverPhotoPath
        location.coverPhotoPath = nil
        try modelContext.save()
        if let oldPath {
            removeManagedPhoto(at: oldPath, libraryURL: libraryURL)
        }
    }

    private static func removeManagedPhoto(at path: String, libraryURL: URL) {
        let url = DocumentLibraryService.locationPhotoURL(for: path, libraryURL: libraryURL)
        try? FileManager.default.removeItem(at: url)
    }

    private static func normalizedName(from rawName: String) throws -> String {
        try StringNormalization.nonEmptyCollapsedWhitespace(rawName, emptyError: DocumentLocationValidationError.emptyName)
    }
}

enum DocumentLocationValidationError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            "Locations need a name."
        }
    }
}
