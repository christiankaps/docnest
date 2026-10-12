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
    var steps: [PipelineStep] = [.init(kind: .rename, template: "{documentDate}_{word1}")]
    var destination: Destination?
    var unattended = false
    var needsText: Bool { steps.contains { $0.kind == .rename && $0.template.contains("{text}") } }
    var needsAnalysis: Bool { steps.contains { $0.kind == .rename && FilenameTemplate.requiresAnalysis($0.template) } }
    var summary: String {
        let actions = steps.map { step in
            step.kind == .rename ? (needsAnalysis ? "Name from document" : "Rename file") : step.title
        }
        return (actions + (destination.map { ["Save to \($0.name)"] } ?? [])).joined(separator: " · ")
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
            try FilenameTemplate.validate(step.template)
        }
        if unattended && (destination == nil || needsText) {
            throw PipeError.message("Unattended pipelines need a destination folder and cannot use {text}.")
        }
    }

    /// Shared by the preflight preview and execution, including every rename step.
    func outputFilename(original: String, text: String, date: Date) throws -> String {
        try outputFilename(values: .init(original: original, manualText: text, processedAt: date))
    }

    func outputFilename(values: NamingValues) throws -> String {
        try validate()
        var result: String?
        for step in steps where step.kind == .rename {
            result = try FilenameTemplate.render(step.template, values: values)
        }
        if let result { return result }
        return try FilenameTemplate.filename(values.original)
    }
}

struct PipelineConfiguration: Codable, Equatable, Sendable {
    var pipelines: [Pipeline] = []
    var defaultID: UUID?

    var solePipelineID: UUID? { pipelines.count == 1 ? pipelines[0].id : nil }

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
