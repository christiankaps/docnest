import Foundation
import SwiftData

enum DocumentDeletionMode {
    case removeFromLibrary
    case deleteStoredFiles
}

enum DeleteDocumentsUseCase {
    enum DeleteDocumentsError: LocalizedError {
        case missingLibraryLocation
        case cleanupRequired(Int)

        var errorDescription: String? {
            switch self {
            case .missingLibraryLocation:
                return "The library location could not be determined for deleting stored PDF files."
            case .cleanupRequired(let count):
                return "\(count) deleted document\(count == 1 ? "" : "s") could not be removed from the library cleanup area. The documents are no longer in the library, but their files remain stored for recovery."
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

        var stagedFiles: [DocumentStorageService.StagedStoredFile] = []
        if mode == .deleteStoredFiles, let libraryURL {
            do {
                for storedFilePath in storedFilePaths {
                    if let stagedFile = try DocumentStorageService.stageStoredFileForDeletion(
                        at: storedFilePath,
                        libraryURL: libraryURL
                    ) {
                        stagedFiles.append(stagedFile)
                    }
                }
            } catch {
                restoreStagedFiles(stagedFiles)
                throw error
            }
        }

        do {
            try ManageLabelValuesUseCase.deleteValues(forDocumentIDs: Set(documents.map(\.id)), using: modelContext)
            for document in documents {
                modelContext.delete(document)
            }
            try modelContext.save()
        } catch {
            modelContext.rollback()
            restoreStagedFiles(stagedFiles)
            throw error
        }

        var cleanupFailures = 0
        for stagedFile in stagedFiles {
            do {
                try DocumentStorageService.permanentlyDeleteStagedStoredFile(stagedFile)
            } catch {
                cleanupFailures += 1
            }
        }
        if cleanupFailures > 0 {
            throw DeleteDocumentsError.cleanupRequired(cleanupFailures)
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

    private static func restoreStagedFiles(_ stagedFiles: [DocumentStorageService.StagedStoredFile]) {
        for stagedFile in stagedFiles.reversed() {
            try? DocumentStorageService.restoreStagedStoredFile(stagedFile)
        }
    }
}
