import Foundation

/// Accepts new payloads without reading the live library. Its receipt never contains library metadata.
actor CaptureInbox {
    struct Receipt: Sendable { let id: UUID }
    private struct Manifest: Codable {
        let schemaVersion: Int
        let id: UUID
        let filename: String
        let capturedAt: Date
    }
    let root: URL
    private let files = FileManager.default
    private var draining = false
    private let protectedLibraryRoots: [URL]
    private var pending: URL { root.appending(path: "Pending") }
    private var staging: URL { root.appending(path: "Staging") }
    static var defaultRoot: URL { URL.applicationSupportDirectory.appending(path: "DocNestCapture") }
    init(root: URL = CaptureInbox.defaultRoot, protectedLibraryRoots: [URL] = [LibraryStore.defaultRoot]) {
        self.root = root
        self.protectedLibraryRoots = protectedLibraryRoots
    }

    func acceptPDF(from source: URL, capturedAt: Date = Date()) throws -> Receipt {
        let canonicalSource = source.resolvingSymlinksInPath().standardizedFileURL.path
        guard !(protectedLibraryRoots + [root]).contains(where: { protected in
            let path = protected.resolvingSymlinksInPath().standardizedFileURL.path
            return canonicalSource == path || canonicalSource.hasPrefix(path + "/")
        }) else { throw LibraryError.invalidCaptureSource }
        try prepareDirectories()
        let id = UUID()
        let transaction = staging.appending(path: id.uuidString)
        try directory(transaction)
        defer { try? files.removeItem(at: transaction) }
        // Keep the final filename for the shared import pipeline, independent of queue directory IDs.
        let filename = LibraryStore.safeFilename(source.lastPathComponent)
        let pdf = transaction.appending(path: filename)
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { url in
            do { try files.copyItem(at: url, to: pdf) } catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        _ = try LibraryStore.validatePDF(at: pdf)
        try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: pdf.path)
        let manifest = Manifest(schemaVersion: 1, id: id, filename: filename, capturedAt: capturedAt)
        try JSONEncoder().encode(manifest).write(to: transaction.appending(path: "capture.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try files.moveItem(at: transaction, to: pending.appending(path: id.uuidString))
        return Receipt(id: id)
    }

    /// A committed capture is removed only after import commits. A crash in between is an exact-content retry.
    func drain(into store: LibraryStore) async throws -> [ImportResult] {
        try store.accessPolicy.requireUnlocked()
        guard !draining else { return [] }
        draining = true
        defer { draining = false }
        try prepareDirectories()
        for abandoned in try files.contentsOfDirectory(at: staging, includingPropertiesForKeys: nil) { try files.removeItem(at: abandoned) }
        var results: [ImportResult] = []
        for folder in try files.contentsOfDirectory(at: pending, includingPropertiesForKeys: nil).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }) {
            try store.accessPolicy.requireUnlocked()
            let manifest: Manifest
            do { manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: folder.appending(path: "capture.json"))) }
            catch { throw LibraryError.invalidCapture }
            guard manifest.schemaVersion == 1, manifest.id.uuidString == folder.lastPathComponent,
                  manifest.filename == LibraryStore.safeFilename(manifest.filename),
                  manifest.capturedAt.timeIntervalSinceReferenceDate.isFinite else { throw LibraryError.invalidCapture }
            let result = try await store.importPDF(from: folder.appending(path: manifest.filename), importedAt: manifest.capturedAt)
            try files.removeItem(at: folder)
            results.append(result)
        }
        return results
    }

    private func prepareDirectories() throws { try directory(pending); try directory(staging) }
    private func directory(_ url: URL) throws {
        try files.createDirectory(at: url, withIntermediateDirectories: true,
            attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }
}
