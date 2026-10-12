import Foundation

struct NamingValues: Sendable {
    var original: String
    var manualText: String
    var processedAt: Date
    var documentDate: String?
    var dateAmbiguous = false
    var words: [String] = []
}

enum FilenameTemplate {
    enum Token: String, Sendable, CaseIterable {
        case original, date, text, documentDate, word1, word2, word3
        var title: String {
            switch self {
            case .original: "Original name"
            case .date: "Processing date"
            case .text: "Manual text"
            case .documentDate: "Document date"
            case .word1: "Word 1"
            case .word2: "Word 2"
            case .word3: "Word 3"
            }
        }
        var needsAnalysis: Bool {
            switch self { case .documentDate, .word1, .word2, .word3: true; default: false }
        }
    }

    enum Part: Equatable, Sendable {
        case literal(String)
        case token(Token)
        var source: String {
            switch self {
            case .literal(let value): value
            case .token(let token): "{\(token.rawValue)}"
            }
        }
        var title: String {
            switch self { case .literal(let value): value; case .token(let token): token.title }
        }
    }

    static func parse(_ source: String) throws -> [Part] {
        var parts: [Part] = []
        var cursor = source.startIndex
        while cursor < source.endIndex {
            guard let opening = source[cursor...].firstIndex(of: "{") else {
                let tail = String(source[cursor...])
                guard !tail.contains("}") else { throw invalidToken() }
                if !tail.isEmpty { parts.append(.literal(tail)) }
                break
            }
            let literal = String(source[cursor..<opening])
            guard !literal.contains("}") else { throw invalidToken() }
            if !literal.isEmpty { parts.append(.literal(literal)) }
            guard let closing = source[opening...].firstIndex(of: "}") else { throw invalidToken() }
            let name = String(source[source.index(after: opening)..<closing])
            guard let token = Token(rawValue: name) else { throw invalidToken() }
            parts.append(.token(token))
            cursor = source.index(after: closing)
        }
        return parts
    }

    static func source(_ parts: [Part]) -> String { parts.map(\.source).joined() }
    static func requiresAnalysis(_ source: String) -> Bool {
        guard let parts = try? parse(source) else { return false }
        return parts.contains { if case .token(let token) = $0 { token.needsAnalysis } else { false } }
    }

    static func validate(_ source: String) throws {
        let parts = try parse(source)
        _ = try render(parts, values: .init(original: "Document", manualText: "Example", processedAt: Date(),
            documentDate: "2026-10-05", words: ["Example", "Second", "Third"]))
    }

    static func render(_ source: String, values: NamingValues) throws -> String {
        try render(parse(source), values: values)
    }

    static func render(_ parts: [Part], values: NamingValues) throws -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        var stem = ""
        for part in parts {
            switch part {
            case .literal(let value): stem += value
            case .token(let token):
                switch token {
                case .original: stem += values.original
                case .date: stem += formatter.string(from: values.processedAt)
                case .text:
                    guard !values.manualText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
                        throw PipeError.message("Enter the text required by this filename template.")
                    }
                    stem += values.manualText
                case .documentDate:
                    guard !values.dateAmbiguous else {
                        throw PipeError.message("Several document dates are plausible. Choose the correct date before naming this file.")
                    }
                    stem += values.documentDate ?? formatter.string(from: values.processedAt)
                case .word1, .word2, .word3:
                    let index = token == .word1 ? 0 : token == .word2 ? 1 : 2
                    guard values.words.indices.contains(index) else {
                        throw PipeError.message("This filename needs Word \(index + 1). Choose or enter a meaningful word.")
                    }
                    stem += values.words[index]
                }
            }
        }
        return try filename(stem)
    }

    static func render(_ template: String, original: String, text: String, date: Date) throws -> String {
        try render(template, values: .init(original: original, manualText: text, processedAt: date))
    }

    static func filename(_ value: String) throws -> String {
        let stem = value.lowercased().hasSuffix(".pdf") ? String(value.dropLast(4)) : value
        let forbidden = CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/\\:"))
        let clean = stem.components(separatedBy: forbidden).joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean != ".", clean != "..", !clean.hasPrefix(".") else {
            throw PipeError.message("Enter a visible, non-empty filename.")
        }
        guard clean.utf8.count <= 180 else { throw PipeError.message("The filename is too long (maximum 180 bytes before .pdf).") }
        return clean + ".pdf"
    }

    private static func invalidToken() -> PipeError {
        .message("Use filename chips or supported tokens: {original}, {date}, {text}, {documentDate}, and {word1}–{word3}.")
    }
}
