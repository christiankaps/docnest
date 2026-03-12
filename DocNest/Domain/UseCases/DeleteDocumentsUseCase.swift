import Foundation
import SwiftData

enum DocumentDeletionMode {
    case removeFromLibrary
    case deleteStoredFiles
}

enum DeleteDocumentsUseCase {
    enum DeleteDocumentsError: LocalizedError {
        case missingLibraryLocation

        var errorDescription: String? {
            switch self {
            case .missingLibraryLocation:
                return "The library location could not be determined for deleting stored PDF files."
            }
        }
    }

    static func execute(
        _ documents: [DocumentRecord],
        mode: DocumentDeletionMode,
        libraryURL: URL?,
        using modelContext: ModelContext
    ) throws {
        guard !documents.isEmpty else {
            return
        }

        let storedFilePaths = Set(documents.compactMap(\.storedFilePath))

        if mode == .deleteStoredFiles, !storedFilePaths.isEmpty, libraryURL == nil {
            throw DeleteDocumentsError.missingLibraryLocation
        }

        for document in documents {
            modelContext.delete(document)
        }

        try modelContext.save()

        guard mode == .deleteStoredFiles, let libraryURL else {
            return
        }

        for storedFilePath in storedFilePaths {
            DocumentStorageService.deleteStoredFile(at: storedFilePath, libraryURL: libraryURL)
        }
    }

    static func moveToBin(_ documents: [DocumentRecord], using modelContext: ModelContext) throws {
        guard !documents.isEmpty else {
            return
        }

        let now = Date()
        var didChange = false

        for document in documents where document.trashedAt == nil {
            document.trashedAt = now
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }
    }

    static func restoreFromBin(_ documents: [DocumentRecord], using modelContext: ModelContext) throws {
        guard !documents.isEmpty else {
            return
        }

        var didChange = false

        for document in documents where document.trashedAt != nil {
            document.trashedAt = nil
            didChange = true
        }

        if didChange {
            try modelContext.save()
        }
    }
}