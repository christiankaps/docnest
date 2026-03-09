import Foundation

enum DocumentStorageService {
    static var storageDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport
            .appendingPathComponent("com.kaps.docnest", isDirectory: true)
            .appendingPathComponent("Documents", isDirectory: true)
    }

    static func ensureStorageDirectoryExists() throws {
        try FileManager.default.createDirectory(
            at: storageDirectory,
            withIntermediateDirectories: true
        )
    }

    static func copyToStorage(from sourceURL: URL, documentID: UUID) throws -> String {
        try ensureStorageDirectoryExists()
        let ext = sourceURL.pathExtension
        let destinationURL = storageDirectory
            .appendingPathComponent(documentID.uuidString)
            .appendingPathExtension(ext)
        try FileManager.default.copyItem(at: sourceURL, to: destinationURL)
        return destinationURL.path
    }

    static func deleteStoredFile(at path: String) {
        try? FileManager.default.removeItem(atPath: path)
    }

    static func fileURL(for path: String) -> URL {
        URL(fileURLWithPath: path)
    }

    static func fileExists(at path: String) -> Bool {
        FileManager.default.fileExists(atPath: path)
    }
}
