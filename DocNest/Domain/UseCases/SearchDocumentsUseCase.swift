import Foundation
import SwiftData

enum SearchDocumentsUseCase {
    struct Snapshot: Sendable {
        let documentID: UUID
        let labelIDs: Set<UUID>
        let title: String
        let originalFileName: String
        let labelNames: [String]
        let fullText: String?
    }

    static func filter(
        _ documents: [DocumentRecord],
        query: String,
        selectedLabelIDs: Set<PersistentIdentifier>
    ) -> [DocumentRecord] {
        let searchTerms = normalizedSearchTerms(from: query)

        return documents.filter { document in
            matchesAllSelectedLabels(document, selectedLabelIDs: selectedLabelIDs)
                && matchesAllSearchTerms(document, searchTerms: searchTerms)
        }
    }

    static func filter(
        _ documents: [Snapshot],
        query: String,
        selectedLabelIDs: Set<UUID>
    ) throws -> [Snapshot] {
        let searchTerms = normalizedSearchTerms(from: query)
        var matches: [Snapshot] = []
        matches.reserveCapacity(documents.count)

        for (index, document) in documents.enumerated() {
            if index.isMultiple(of: 64) {
                try Task.checkCancellation()
            }

            if matchesAllSelectedLabels(document, selectedLabelIDs: selectedLabelIDs)
                && matchesAllSearchTerms(document, searchTerms: searchTerms) {
                matches.append(document)
            }
        }

        return matches
    }

    private static func matchesAllSelectedLabels(_ document: DocumentRecord, selectedLabelIDs: Set<PersistentIdentifier>) -> Bool {
        guard !selectedLabelIDs.isEmpty else {
            return true
        }

        guard document.labels.count >= selectedLabelIDs.count else {
            return false
        }

        for selectedLabelID in selectedLabelIDs {
            let hasLabel = document.labels.contains { $0.persistentModelID == selectedLabelID }
            if !hasLabel {
                return false
            }
        }

        return true
    }

    private static func matchesAllSelectedLabels(_ document: Snapshot, selectedLabelIDs: Set<UUID>) -> Bool {
        guard !selectedLabelIDs.isEmpty else {
            return true
        }

        guard document.labelIDs.count >= selectedLabelIDs.count else {
            return false
        }

        for selectedLabelID in selectedLabelIDs where !document.labelIDs.contains(selectedLabelID) {
            return false
        }

        return true
    }

    private static func matchesAllSearchTerms(_ document: DocumentRecord, searchTerms: [String]) -> Bool {
        guard !searchTerms.isEmpty else {
            return true
        }

        for term in searchTerms {
            let titleMatches = document.title.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            if titleMatches {
                continue
            }

            let fileNameMatches = document.originalFileName.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            if fileNameMatches {
                continue
            }

            let labelMatches = document.labels.contains { label in
                label.name.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
            if labelMatches {
                continue
            }

            if let fullText = document.fullText,
               fullText.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                continue
            }

            return false
        }

        return true
    }

    private static func matchesAllSearchTerms(_ document: Snapshot, searchTerms: [String]) -> Bool {
        guard !searchTerms.isEmpty else {
            return true
        }

        for term in searchTerms {
            if document.title.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                continue
            }

            if document.originalFileName.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                continue
            }

            if document.labelNames.contains(where: {
                $0.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }) {
                continue
            }

            if let fullText = document.fullText,
               fullText.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil {
                continue
            }

            return false
        }

        return true
    }

    static func normalizedSearchTerms(from query: String) -> [String] {
        query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
