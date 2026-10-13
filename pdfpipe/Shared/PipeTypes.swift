import Foundation

enum PipeError: LocalizedError, Sendable {
    case message(String)
    var errorDescription: String? {
        if case .message(let value) = self { value } else { nil }
    }
}

struct Destination: Codable, Equatable, Sendable {
    var bookmark: Data
    var name: String

    static func selected(_ url: URL) throws -> Destination {
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        return try Destination(bookmark: url.bookmarkData(options: .minimalBookmark,
            includingResourceValuesForKeys: nil, relativeTo: nil), name: url.lastPathComponent)
    }

    func resolve() throws -> URL {
        var stale = false
        let url = try URL(resolvingBookmarkData: bookmark, options: .withoutUI, relativeTo: nil,
            bookmarkDataIsStale: &stale)
        guard !stale else { throw PipeError.message("Folder access expired. Choose the folder again in Settings.") }
        return url
    }
}

enum SafeFilename {
    static func pdf(_ value: String) throws -> String {
        let stem = value.lowercased().hasSuffix(".pdf") ? String(value.dropLast(4)) : value
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        guard stem.rangeOfCharacter(from: forbidden) == nil,
              stem == stem.trimmingCharacters(in: .whitespacesAndNewlines),
              !stem.isEmpty, stem != ".", stem != "..", !stem.hasPrefix(".") else {
            throw PipeError.message("Enter a visible, non-empty filename.")
        }
        guard stem.utf8.count <= 180 else {
            throw PipeError.message("The filename is too long (maximum 180 bytes before .pdf).")
        }
        return stem + ".pdf"
    }
}
