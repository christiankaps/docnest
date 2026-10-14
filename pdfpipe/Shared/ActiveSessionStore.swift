import Foundation

/// One unfinished app draft. The file lives beside the temporary session and is
/// removed when the user exports or discards it; it is not a document library.
enum ActiveSessionStore {
    struct Snapshot: Codable, Sendable {
        var id: UUID
        var originalName: String
        var sourceFormat: String
        var processingDate: Date
        var composer: FilenameComposer
        var manualWord: String
    }

    private static func url(root: URL) -> URL {
        root.appendingPathComponent("active-app-session.json")
    }

    static func load(root: URL) throws -> Snapshot? {
        let file = url(root: root)
        guard FileManager.default.fileExists(atPath: file.path) else { return nil }
        return try JSONDecoder().decode(Snapshot.self, from: Data(contentsOf: file))
    }

    static func save(_ snapshot: Snapshot, root: URL) throws {
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try JSONEncoder().encode(snapshot).write(to: url(root: root), options: .atomic)
    }

    static func clear(id: UUID, root: URL) throws {
        let file = url(root: root)
        guard FileManager.default.fileExists(atPath: file.path) else { return }
        let stored = try? load(root: root)
        guard stored == nil || stored?.id == id else { return }
        try FileManager.default.removeItem(at: file)
    }

    static func clear(root: URL) throws {
        let file = url(root: root)
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
    }
}
