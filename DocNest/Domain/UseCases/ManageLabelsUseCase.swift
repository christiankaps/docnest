import Foundation
import SwiftData

enum ManageLabelsUseCase {
    static func matchingAllSelectedLabels(_ document: DocumentRecord, selectedLabelIDs: Set<PersistentIdentifier>) -> Bool {
        guard !selectedLabelIDs.isEmpty else {
            return true
        }

        let documentLabelIDs = Set(document.labels.map(\.persistentModelID))
        return selectedLabelIDs.isSubset(of: documentLabelIDs)
    }

    @discardableResult
    static func createLabel(named name: String, using modelContext: ModelContext) throws -> LabelTag {
        let result = try createOrFetchLabel(named: name, using: modelContext)

        if result.didCreateLabel {
            try modelContext.save()
        }

        return result.label
    }

    @discardableResult
    static func createAndAssignLabel(named name: String, to document: DocumentRecord, using modelContext: ModelContext) throws -> LabelTag {
        let result = try createOrFetchLabel(named: name, using: modelContext)
        let didChangeAssignments = assign(result.label, to: document)

        if result.didCreateLabel || didChangeAssignments {
            try modelContext.save()
        }

        return result.label
    }

    static func assign(_ label: LabelTag, to document: DocumentRecord, using modelContext: ModelContext) throws {
        if assign(label, to: document) {
            try modelContext.save()
        }
    }

    static func remove(_ label: LabelTag, from document: DocumentRecord, using modelContext: ModelContext) throws {
        let originalCount = document.labels.count
        document.labels.removeAll { $0.persistentModelID == label.persistentModelID }

        if document.labels.count != originalCount {
            try modelContext.save()
        }
    }

    @discardableResult
    static func rename(_ label: LabelTag, to newName: String, using modelContext: ModelContext) throws -> LabelTag {
        let normalizedName = try normalizedLabelName(from: newName)

        if label.name.caseInsensitiveCompare(normalizedName) == .orderedSame {
            if label.name != normalizedName {
                label.name = normalizedName
                try modelContext.save()
            }
            return label
        }

        if let existingLabel = try existingLabel(named: normalizedName, using: modelContext),
           existingLabel.persistentModelID != label.persistentModelID {
            for document in Array(label.documents) {
                _ = assign(existingLabel, to: document)
                document.labels.removeAll { $0.persistentModelID == label.persistentModelID }
            }

            modelContext.delete(label)
            try modelContext.save()
            return existingLabel
        }

        label.name = normalizedName
        try modelContext.save()
        return label
    }

    static func delete(_ label: LabelTag, using modelContext: ModelContext) throws {
        for document in Array(label.documents) {
            document.labels.removeAll { $0.persistentModelID == label.persistentModelID }
        }

        modelContext.delete(label)
        try modelContext.save()
    }

    private static func createOrFetchLabel(named name: String, using modelContext: ModelContext) throws -> LabelMutationResult {
        let normalizedName = try normalizedLabelName(from: name)

        if let existingLabel = try existingLabel(named: normalizedName, using: modelContext) {
            return LabelMutationResult(label: existingLabel, didCreateLabel: false)
        }

        let label = LabelTag(name: normalizedName)
        modelContext.insert(label)
        return LabelMutationResult(label: label, didCreateLabel: true)
    }

    private static func existingLabel(named normalizedName: String, using modelContext: ModelContext) throws -> LabelTag? {
        let descriptor = FetchDescriptor<LabelTag>(sortBy: [SortDescriptor(\.name, order: .forward)])
        let labels = try modelContext.fetch(descriptor)
        return labels.first {
            $0.name.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }
    }

    private static func normalizedLabelName(from rawName: String) throws -> String {
        let collapsedWhitespace = rawName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsedWhitespace.isEmpty else {
            throw LabelValidationError.emptyName
        }

        return collapsedWhitespace
    }

    @discardableResult
    private static func assign(_ label: LabelTag, to document: DocumentRecord) -> Bool {
        guard !document.labels.contains(where: { $0.persistentModelID == label.persistentModelID }) else {
            return false
        }

        document.labels.append(label)
        document.labels.sort {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
        return true
    }
}

struct LabelMutationResult {
    let label: LabelTag
    let didCreateLabel: Bool
}

enum LabelValidationError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Labels need a name."
        }
    }
}