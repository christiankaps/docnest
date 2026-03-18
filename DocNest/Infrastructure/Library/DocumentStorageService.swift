import Foundation

enum DocumentStorageService {
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
    /// Returns the updated relative path, or the original path if renaming is not possible.
    static func renameStoredFile(
        at currentPath: String,
        newTitle: String,
        contentHash: String,
        libraryURL: URL
    ) -> String {
        let currentURL = fileURL(for: currentPath, libraryURL: libraryURL)
        guard FileManager.default.fileExists(atPath: currentURL.path) else {
            return currentPath
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
            return currentPath
        }

        do {
            try FileManager.default.moveItem(at: currentURL, to: newURL)
            return relativePath(of: newURL, in: libraryURL)
        } catch {
            return currentPath
        }
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

    // MARK: - Private helpers

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