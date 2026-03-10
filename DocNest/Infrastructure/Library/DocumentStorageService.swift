import Foundation

enum DocumentStorageService {
    static func copyToStorage(
        from sourceURL: URL,
        documentID: UUID,
        importedAt: Date,
        libraryURL: URL
    ) throws -> String {
        let destinationDirectory = storageDirectory(for: importedAt, libraryURL: libraryURL)
        try FileManager.default.createDirectory(
            at: destinationDirectory,
            withIntermediateDirectories: true
        )

        let ext = sourceURL.pathExtension
        let destinationURL = destinationDirectory
            .appendingPathComponent(documentID.uuidString)
            .appendingPathExtension(ext)

        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL.path.replacingOccurrences(of: libraryURL.path + "/", with: "")
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

    private static func storageDirectory(for importedAt: Date, libraryURL: URL) -> URL {
        let components = Calendar.current.dateComponents([.year, .month], from: importedAt)
        let year = String(components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 1)

        return DocumentLibraryService.originalsDirectory(for: libraryURL)
            .appendingPathComponent(year, isDirectory: true)
            .appendingPathComponent(month, isDirectory: true)
    }
}