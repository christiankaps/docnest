import Foundation
import Combine

@MainActor
final class PipelineStore: ObservableObject {
    @Published private(set) var configuration = PipelineConfiguration()
    @Published private(set) var error: String?
    private let defaults: UserDefaults?
    private static let key = "pipelines.v1"

    init(defaults: UserDefaults? = nil) {
        if let defaults { self.defaults = defaults }
        else if let group = Bundle.main.object(forInfoDictionaryKey: "PdfPipeAppGroup") as? String,
                FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: group) != nil {
            self.defaults = UserDefaults(suiteName: group)
        } else { self.defaults = nil }
        reload()
    }

    func reload() {
        guard let defaults else {
            error = "Shared configuration is unavailable. Enable the PDF Pipe App Group for both targets when signing the app."
            return
        }
        do {
            if let data = defaults.data(forKey: Self.key) {
                configuration = try JSONDecoder().decode(PipelineConfiguration.self, from: data)
            } else { configuration = .init() }
            error = nil
        } catch {
            self.error = "Saved pipelines could not be read. Existing configuration has not been replaced."
        }
    }

    private func write(_ value: PipelineConfiguration) throws {
        guard let defaults, error == nil else { throw PipeError.message(error ?? "Configuration is unavailable.") }
        let data = try JSONEncoder().encode(value)
        defaults.set(data, forKey: Self.key)
        configuration = value
    }

    func save(_ pipeline: Pipeline, isDefault: Bool) throws {
        try pipeline.validate()
        if isDefault && !pipeline.unattended { throw PipeError.message("The default pipeline must run unattended.") }
        var next = configuration
        if let index = next.pipelines.firstIndex(where: { $0.id == pipeline.id }) { next.pipelines[index] = pipeline }
        else { next.pipelines.append(pipeline) }
        if isDefault { next.defaultID = pipeline.id }
        else if next.defaultID == pipeline.id { next.defaultID = nil }
        try write(next)
    }

    func duplicate(_ pipeline: Pipeline) throws {
        var copy = pipeline
        copy.id = UUID()
        copy.name += " copy"
        try save(copy, isDefault: false)
    }

    func delete(_ pipeline: Pipeline) throws {
        var next = configuration
        next.pipelines.removeAll { $0.id == pipeline.id }
        if next.defaultID == pipeline.id { next.defaultID = nil }
        try write(next)
    }
}
