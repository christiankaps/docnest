import Foundation

enum PipeError: LocalizedError, Sendable {
    case message(String)
    var errorDescription: String? {
        if case .message(let value) = self { value } else { nil }
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
