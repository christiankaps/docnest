import Foundation

struct PipelineStep: Codable, Identifiable, Equatable, Sendable {
    enum Kind: String, Codable, CaseIterable, Sendable { case ocr, rename }
    var id = UUID()
    var kind: Kind
    var template = "{date}_{original}"
    var skipExistingText = true
    var title: String { kind == .ocr ? "Make searchable" : "Rename" }

    private enum CodingKeys: String, CodingKey { case id, kind, template, skipExistingText }

    init(id: UUID = UUID(), kind: Kind, template: String = "{date}_{original}", skipExistingText: Bool = true) {
        self.id = id
        self.kind = kind
        self.template = template
        self.skipExistingText = skipExistingText
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        id = try values.decode(UUID.self, forKey: .id)
        kind = try values.decode(Kind.self, forKey: .kind)
        template = try values.decode(String.self, forKey: .template)
        skipExistingText = try values.decodeIfPresent(Bool.self, forKey: .skipExistingText) ?? true
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
        guard !stale else { throw PipeError.message("Folder access has expired. Choose the destination again in PDF Pipe.") }
        return url
    }
}

struct Pipeline: Codable, Identifiable, Equatable, Sendable {
    var id = UUID()
    var name = "New pipeline"
    var steps: [PipelineStep] = [.init(kind: .rename)]
    var destination: Destination?
    var unattended = false
    var needsText: Bool { steps.contains { $0.kind == .rename && $0.template.contains("{text}") } }
    var summary: String {
        (steps.map(\.title) + (destination == nil ? [] : ["Save to \(destination!.name)"])).joined(separator: " → ")
    }

    /// Saving an editor draft yields one enabled step of each kind in fixed order.
    /// Existing pipelines stay readable; their last rename template seeds the editor.
    func configured(ocr: Bool, rename: Bool, template: String, save: Bool, skipExistingText: Bool = true) throws -> Pipeline {
        var result = self
        result.steps = []
        if ocr { result.steps.append(.init(kind: .ocr, skipExistingText: skipExistingText)) }
        if rename { result.steps.append(.init(kind: .rename, template: template)) }
        if save {
            guard result.destination != nil else {
                throw PipeError.message("Choose a folder for the Save step, or turn Save off.")
            }
        } else {
            result.destination = nil
            result.unattended = false
        }
        try result.validate()
        return result
    }

    func validate() throws {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw PipeError.message("Give the pipeline a name.")
        }
        for step in steps where step.kind == .rename {
            _ = try FilenameTemplate.render(step.template, original: "Document", text: "Example", date: Date())
        }
        if unattended && (destination == nil || needsText) {
            throw PipeError.message("Unattended pipelines need a destination folder and cannot use {text}.")
        }
    }

    /// Shared by the preflight preview and execution, including every rename step.
    func outputFilename(original: String, text: String, date: Date) throws -> String {
        try validate()
        var result: String?
        for step in steps where step.kind == .rename {
            result = try FilenameTemplate.render(step.template, original: original, text: text, date: date)
        }
        if let result { return result }
        return try FilenameTemplate.filename(original)
    }
}

struct PipelineConfiguration: Codable, Equatable, Sendable {
    var pipelines: [Pipeline] = []
    var defaultID: UUID?

    func defaultPipeline() throws -> Pipeline? {
        guard let defaultID else { return nil }
        guard let pipeline = pipelines.first(where: { $0.id == defaultID }), pipeline.unattended else {
            throw PipeError.message("The default pipeline is unavailable or needs review. Choose a pipeline or update the default in PDF Pipe.")
        }
        try pipeline.validate()
        return pipeline
    }
}

enum PipeError: LocalizedError, Sendable {
    case message(String)
    var errorDescription: String? { if case let .message(value) = self { return value }; return nil }
}

enum FilenameTemplate {
    static func render(_ template: String, original: String, text: String, date: Date) throws -> String {
        var tokensRemoved = template
        for token in ["{original}", "{date}", "{text}"] {
            tokensRemoved = tokensRemoved.replacingOccurrences(of: token, with: "")
        }
        guard !tokensRemoved.contains("{"), !tokensRemoved.contains("}") else {
            throw PipeError.message("Use only {original}, {date}, and {text} in filename templates.")
        }
        if template.contains("{text}") && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw PipeError.message("Enter the text required by this filename template.")
        }
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd"
        let expression = try NSRegularExpression(pattern: "\\{(original|date|text)\\}")
        let source = template as NSString
        var result = ""
        var end = 0
        for match in expression.matches(in: template, range: NSRange(location: 0, length: source.length)) {
            result += source.substring(with: NSRange(location: end, length: match.range.location - end))
            switch source.substring(with: match.range(at: 1)) {
            case "original": result += original
            case "date": result += formatter.string(from: date)
            default: result += text
            }
            end = match.range.location + match.range.length
        }
        result += source.substring(from: end)
        return try filename(result)
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
}
