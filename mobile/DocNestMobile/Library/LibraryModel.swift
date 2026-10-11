import Foundation
import Observation

@MainActor @Observable
final class LibraryModel {
    let store: LibraryStore
    let access: LibraryLockController?
    private let captures: CaptureInbox?
    var labels: [LibraryLabel] = []
    var deletedDocuments: [LibraryDocument] = []
    var isSaving = false
    var documents: [LibraryDocument] = []
    var isLoading = true
    var isImporting = false
    var loadError: String?
    var actionError: String?
    var duplicate: LibraryDocument?

    init(store: LibraryStore = LibraryStore(), access: LibraryLockController? = nil, captures: CaptureInbox? = nil) {
        self.store = store
        self.access = access
        self.captures = captures
    }

    func load() async {
        isLoading = true
        loadError = nil
        do {
            documents = try await store.load()
            labels = try await store.allLabels()
            deletedDocuments = try await store.recentlyDeleted()
        }
        catch { loadError = error.localizedDescription }
        isLoading = false
    }

    func importPDF(_ source: URL) async {
        guard !isImporting else { return }
        isImporting = true
        defer { isImporting = false }
        do {
            if let captures {
                _ = try await captures.acceptPDF(from: source)
                if store.accessPolicy.isLocked {
                    access?.captureNotice = String(localized: "PDF saved. Unlock your library to review it.")
                } else {
                    await drainCaptures()
                    if store.accessPolicy.isLocked { access?.captureNotice = String(localized: "PDF saved. Unlock your library to review it.") }
                }
            } else {
                let result = try await store.importPDF(from: source)
                try await refresh()
                if !store.accessPolicy.isLocked && result.isDuplicate { duplicate = result.document }
            }
        } catch {
            if store.accessPolicy.isLocked {
                access?.captureNotice = (error as? LibraryError)?.errorDescription ?? String(localized: "The PDF couldn’t be saved. Try again.")
            } else { actionError = error.localizedDescription }
        }
    }

    func drainCaptures() async {
        guard let captures, !store.accessPolicy.isLocked else { return }
        do {
            let results = try await captures.drain(into: store)
            guard !store.accessPolicy.isLocked else { return }
            try await refresh()
            duplicate = results.last(where: { $0.isDuplicate })?.document
        } catch {
            // Background relocking leaves the remaining queue intact; retry after the next unlock.
            if !store.accessPolicy.isLocked {
                try? await refresh()
                actionError = error.localizedDescription
            }
        }
    }

    private func refresh() async throws {
        let current = try await store.allDocuments()
        let currentLabels = try await store.allLabels()
        let deleted = try await store.recentlyDeleted()
        guard !store.accessPolicy.isLocked else { return }
        documents = current
        labels = currentLabels
        deletedDocuments = deleted
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
            deletedDocuments = try await store.recentlyDeleted()
            return true
        } catch {
            // Cleanup can commit expiry before physical removal fails. Reflect the durable state.
            if let current = try? await store.allDocuments() { documents = current }
            if let deleted = try? await store.recentlyDeleted() { deletedDocuments = deleted }
            actionError = error.localizedDescription
            return false
        }
    }

}
