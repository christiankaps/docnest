import Foundation

struct FilenameComposer: Codable, Equatable, Sendable {
    enum Separator: String, Codable, CaseIterable, Sendable { case dash = "-", underscore = "_" }
    struct Part: Codable, Identifiable, Equatable, Sendable {
        var id: String
        var value: String
        var preceding: Separator?
    }

    private(set) var parts: [Part] = []
    private(set) var undoParts: [Part]?
    var separator: Separator = .dash

    var stem: String {
        parts.enumerated().map { index, part in
            (index == 0 ? "" : (part.preceding ?? .dash).rawValue) + part.value
        }.joined()
    }
    var filename: String { stem + ".pdf" }
    var validFilename: Result<String, Error> { Result { try SafeFilename.pdf(filename) } }

    func order(of id: String) -> Int? { parts.firstIndex { $0.id == id }.map { $0 + 1 } }

    mutating func toggle(id: String, value: String) {
        undoParts = nil
        if let index = parts.firstIndex(where: { $0.id == id }) {
            parts.remove(at: index)
            if !parts.isEmpty { parts[0].preceding = nil }
        } else {
            append(id: id, value: value)
        }
    }

    mutating func append(id: String = UUID().uuidString, value: String) {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        undoParts = nil
        parts.append(Part(id: id, value: trimmed, preceding: parts.isEmpty ? nil : separator))
    }

    mutating func editCompleteName(_ value: String) {
        if undoParts == nil { undoParts = parts }
        let stem = value.lowercased().hasSuffix(".pdf") ? String(value.dropLast(4)) : value
        parts = [Part(id: "custom", value: stem, preceding: nil)]
    }

    mutating func undoEdit() {
        guard let undoParts else { return }
        parts = undoParts
        self.undoParts = nil
    }
}
