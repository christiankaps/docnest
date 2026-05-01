import Foundation

/// Maps imported documents onto stable storage paths inside `Originals/`.
///
/// Storage layout is intentionally hidden behind this service so filename rules,
/// collision handling, and relative-path semantics stay consistent across import,
/// rename, export, and deletion workflows.
enum DocumentStorageService {
    enum StoredFileRestoreError: LocalizedError {
        case renamedFileMissing(String)

        var errorDescription: String? {
            switch self {
            case .renamedFileMissing(let path):
                return "The renamed stored file could not be found at \(path)."
            }
        }
    }

    struct StoredFileRenameResult {
        let originalPath: String
        let updatedPath: String
        let movedFile: Bool
    }

    /// Copies an imported source file into the library's managed storage area and
    /// returns the stored file's path relative to the library root.
    static func copyToStorage(
        from sourceURL: URL,
        title: String,
        contentHash: String,
        importedAt: Date,
        libraryURL: URL
    ) throws -> String {
        let destinationDirectory = storageDirectory(for: importedAt, libraryURL: libraryURL)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        let ext = sourceURL.pathExtension
        let baseName = sanitizeForFilesystem(title)
        let destinationURL = resolveCollision(
            baseName: baseName,
            extension: ext,
            contentHash: contentHash,
            in: destinationDirectory
        )

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return relativePath(of: destinationURL, in: libraryURL)
    }

    /// Renames the stored file to match a new document title.
    /// Returns the updated relative path and enough rollback state for callers that
    /// must keep filesystem and metadata changes transactional.
    static func renameStoredFile(
        at currentPath: String,
        newTitle: String,
        contentHash: String,
        libraryURL: URL
    ) throws -> StoredFileRenameResult {
        let currentURL = fileURL(for: currentPath, libraryURL: libraryURL)
        guard FileManager.default.fileExists(atPath: currentURL.path) else {
            return StoredFileRenameResult(
                originalPath: currentPath,
                updatedPath: currentPath,
                movedFile: false
            )
        }

        let directory = currentURL.deletingLastPathComponent()
        let ext = currentURL.pathExtension
        let baseName = sanitizeForFilesystem(newTitle)
        let newURL = resolveCollision(
            baseName: baseName,
            extension: ext,
            contentHash: contentHash,
            in: directory,
            excluding: currentURL
        )

        // If the resolved name is the same file, no rename needed
        guard newURL != currentURL else {
            return StoredFileRenameResult(
                originalPath: currentPath,
                updatedPath: currentPath,
                movedFile: false
            )
        }

        try FileManager.default.moveItem(at: currentURL, to: newURL)
        return StoredFileRenameResult(
            originalPath: currentPath,
            updatedPath: relativePath(of: newURL, in: libraryURL),
            movedFile: true
        )
    }

    static func restoreRenamedStoredFile(
        _ renameResult: StoredFileRenameResult,
        libraryURL: URL
    ) throws {
        guard renameResult.movedFile else { return }

        let updatedURL = fileURL(for: renameResult.updatedPath, libraryURL: libraryURL)
        let originalURL = fileURL(for: renameResult.originalPath, libraryURL: libraryURL)
        guard updatedURL != originalURL else { return }
        guard FileManager.default.fileExists(atPath: updatedURL.path) else {
            throw StoredFileRestoreError.renamedFileMissing(renameResult.updatedPath)
        }

        try FileManager.default.createDirectory(
            at: originalURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try FileManager.default.moveItem(at: updatedURL, to: originalURL)
    }

    static func deleteStoredFile(at path: String, libraryURL: URL) {
        try? FileManager.default.removeItem(at: fileURL(for: path, libraryURL: libraryURL))
    }

    static func fileURL(for path: String, libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent(path, isDirectory: false)
    }

    static func fileExists(at path: String, libraryURL: URL) -> Bool {
        FileManager.default.fileExists(atPath: fileURL(for: path, libraryURL: libraryURL).path)
    }

    static func fileExistsAsync(at path: String, libraryURL: URL) async -> Bool {
        await Task.detached(priority: .utility) {
            FileManager.default.fileExists(
                atPath: fileURL(for: path, libraryURL: libraryURL).path
            )
        }.value
    }

    // MARK: - Private helpers

    /// Buckets stored originals by import year and month to avoid a single large
    /// flat directory inside the library package.
    private static func storageDirectory(for importedAt: Date, libraryURL: URL) -> URL {
        let components = Calendar.current.dateComponents([.year, .month], from: importedAt)
        let year = String(components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 1)

        return DocumentLibraryService.originalsDirectory(for: libraryURL)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
    }

    private static func relativePath(of url: URL, in libraryURL: URL) -> String {
        url.path.replacingOccurrences(of: libraryURL.path + "/", with: "")
    }

    private static func sanitizeForFilesystem(_ input: String) -> String {
        let illegal = CharacterSet(charactersIn: "/:\\")
        let sanitized = input.components(separatedBy: illegal).joined(separator: "_")
        let trimmed = sanitized.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? "Untitled" : trimmed
    }

    /// Returns a destination URL for the given base name, appending a short hash suffix on collision.
    private static func resolveCollision(
        baseName: String,
        extension ext: String,
        contentHash: String,
        in directory: URL,
        excluding: URL? = nil
    ) -> URL {
        let candidate = directory
            .appendingPathComponent(baseName)
            .appendingPathExtension(ext)

        if !FileManager.default.fileExists(atPath: candidate.path) || candidate == excluding {
            return candidate
        }

        // Append short hash suffix to resolve collision
        let shortHash = String(contentHash.prefix(8))
        let fallback = directory
            .appendingPathComponent("\(baseName) (\(shortHash))")
            .appendingPathExtension(ext)

        if !FileManager.default.fileExists(atPath: fallback.path) || fallback == excluding {
            return fallback
        }

        // Extremely unlikely: both collide, use full hash
        return directory
            .appendingPathComponent("\(baseName) (\(contentHash))")
            .appendingPathExtension(ext)
    }
}
