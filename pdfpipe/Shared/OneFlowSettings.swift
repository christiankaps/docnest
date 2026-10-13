import Foundation
import Combine

/// New settings never read a legacy pipeline or inherit its destination.
@MainActor
final class OneFlowSettingsStore: ObservableObject {
    @Published private(set) var destination: Destination?
    @Published var error: String?
    private let defaults: UserDefaults?
    private static let key = "oneFlow.v1"

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
            error = "Shared settings are unavailable. Check App Group signing."
            return
        }
        do {
            destination = try defaults.data(forKey: Self.key).map { try JSONDecoder().decode(Destination.self, from: $0) }
            error = nil
        } catch {
            self.error = "Saved folder access could not be read. Choose a folder again."
            destination = nil
        }
    }

    func choose(_ url: URL) throws {
        guard let defaults else { throw PipeError.message("Shared settings are unavailable.") }
        let selected = try Destination.selected(url)
        defaults.set(try JSONEncoder().encode(selected), forKey: Self.key)
        destination = selected
        error = nil
    }

    func clear() {
        defaults?.removeObject(forKey: Self.key)
        destination = nil
        error = nil
    }
}
