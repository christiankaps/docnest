import SwiftData

enum SearchDocumentsUseCase {
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

    private static func matchesAllSelectedLabels(_ document: DocumentRecord, selectedLabelIDs: Set<PersistentIdentifier>) -> Bool {
        guard !selectedLabelIDs.isEmpty else {
            return true
        }

        for selectedLabelID in selectedLabelIDs {
            let hasLabel = document.labels.contains { $0.persistentModelID == selectedLabelID }
            if !hasLabel {
                return false
            }
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

    private static func normalizedSearchTerms(from query: String) -> [String] {
        query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
