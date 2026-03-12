import SwiftData

enum SearchDocumentsUseCase {
    static func matches(_ document: DocumentRecord, query: String) -> Bool {
        let searchTerms = normalizedSearchTerms(from: query)
        guard !searchTerms.isEmpty else {
            return true
        }

        let searchableValues = searchableValues(for: document)
        return searchTerms.allSatisfy { term in
            searchableValues.contains { value in
                value.range(of: term, options: [.caseInsensitive, .diacriticInsensitive]) != nil
            }
        }
    }

    static func filter(
        _ documents: [DocumentRecord],
        query: String,
        selectedLabelIDs: Set<PersistentIdentifier>
    ) -> [DocumentRecord] {
        documents.filter { document in
            matchesAllSelectedLabels(document, selectedLabelIDs: selectedLabelIDs)
                && matches(document, query: query)
        }
    }

    private static func matchesAllSelectedLabels(_ document: DocumentRecord, selectedLabelIDs: Set<PersistentIdentifier>) -> Bool {
        guard !selectedLabelIDs.isEmpty else {
            return true
        }

        let documentLabelIDs = Set(document.labels.map(\.persistentModelID))
        return selectedLabelIDs.isSubset(of: documentLabelIDs)
    }

    private static func searchableValues(for document: DocumentRecord) -> [String] {
        var values = [document.title, document.originalFileName]
        values.append(contentsOf: document.labels.map(\.name))
        return values
    }

    private static func normalizedSearchTerms(from query: String) -> [String] {
        query
            .components(separatedBy: .whitespacesAndNewlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }
}
