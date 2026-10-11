import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    let store: LibraryStore
    var documents: [LibraryDocument] = []
    var isLoading = true
    var isImporting = false
    var loadError: String?
    var actionError: String?
    var duplicate: LibraryDocument?

    init(store: LibraryStore = LibraryStore()) { self.store = store }

    func load() async {
        isLoading = true
        loadError = nil
        do { documents = try await store.load() }
        catch { loadError = error.localizedDescription }
        isLoading = false
    }

    func importPDF(_ source: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            let result = try await store.importPDF(from: source)
            documents = try await store.allDocuments()
            if result.isDuplicate { duplicate = result.document }
        } catch {
            actionError = error.localizedDescription
        }
    }
}
