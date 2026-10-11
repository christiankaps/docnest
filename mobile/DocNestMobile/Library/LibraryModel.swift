import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    let store: LibraryStore
    var labels: [LibraryLabel] = []
    var isSaving = false
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
        do { documents = try await store.load(); labels = try await store.allLabels() }
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

    func document(_ id: UUID) -> LibraryDocument? { documents.first { $0.id == id } }
    var inboxCount: Int { documents.filter { $0.reviewState == .inbox }.count }
    var years: [Int] { Set(documents.map { $0.documentDate.year }).sorted(by: >) }
    func labels(for record: LibraryDocument) -> [LibraryLabel] { labels.filter { record.labelIDs.contains($0.id) } }

    @discardableResult
    func save(_ action: () async throws -> Void) async -> Bool {
        guard !isSaving else { return false }
        isSaving = true
        defer { isSaving = false }
        do {
            try await action()
            documents = try await store.allDocuments()
            labels = try await store.allLabels()
            return true
        } catch { actionError = error.localizedDescription; return false }
    }

}
