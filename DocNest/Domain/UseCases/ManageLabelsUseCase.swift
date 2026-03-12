import Foundation
import SwiftData

enum ManageLabelsUseCase {
    @discardableResult
    static func createLabel(named name: String, using modelContext: ModelContext) throws -> LabelTag {
        try createLabel(named: name, color: .blue, using: modelContext)
    }

    @discardableResult
    static func createLabel(named name: String, color: LabelColor, using modelContext: ModelContext) throws -> LabelTag {
        let result = try createOrFetchLabel(named: name, color: color, using: modelContext)

        if result.didCreateLabel {
            try modelContext.save()
        }

        return result.label
    }

    @discardableResult
    static func createAndAssignLabel(named name: String, to document: DocumentRecord, using modelContext: ModelContext) throws -> LabelTag {
        try createAndAssignLabel(named: name, to: [document], using: modelContext)
    }

    @discardableResult
    static func createAndAssignLabel(named name: String, to documents: [DocumentRecord], using modelContext: ModelContext) throws -> LabelTag {
        let result = try createOrFetchLabel(named: name, using: modelContext)
        let didChangeAssignments = assign(result.label, to: documents)

        if result.didCreateLabel || didChangeAssignments {
            try modelContext.save()
        }

        return result.label
    }

    static func assign(_ label: LabelTag, to document: DocumentRecord, using modelContext: ModelContext) throws {
        try assign(label, to: [document], using: modelContext)
    }

    static func assign(_ label: LabelTag, to documents: [DocumentRecord], using modelContext: ModelContext) throws {
        if assign(label, to: documents) {
            try modelContext.save()
        }
    }

    static func remove(_ label: LabelTag, from document: DocumentRecord, using modelContext: ModelContext) throws {
        try remove(label, from: [document], using: modelContext)
    }

    static func remove(_ label: LabelTag, from documents: [DocumentRecord], using modelContext: ModelContext) throws {
        if remove(label, from: documents) {
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

    static func changeColor(of label: LabelTag, to color: LabelColor, using modelContext: ModelContext) throws {
        label.labelColor = color
        try modelContext.save()
    }

    static func reorderLabels(from source: IndexSet, to destination: Int, labels: [LabelTag], using modelContext: ModelContext) throws {
        var reorderedLabels = labels
        reorderedLabels.move(fromOffsets: source, toOffset: destination)

        for (index, label) in reorderedLabels.enumerated() {
            label.sortOrder = index
        }

        try modelContext.save()
    }

    private static func createOrFetchLabel(named name: String, color: LabelColor = .blue, using modelContext: ModelContext) throws -> LabelMutationResult {
        let normalizedName = try normalizedLabelName(from: name)

        let descriptor = FetchDescriptor<LabelTag>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        let allLabels = try modelContext.fetch(descriptor)

        if let existingLabel = allLabels.first(where: {
            $0.name.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            return LabelMutationResult(label: existingLabel, didCreateLabel: false)
        }

        let nextSortOrder = (allLabels.map(\.sortOrder).max() ?? -1) + 1
        let label = LabelTag(name: normalizedName, colorName: color.rawValue, sortOrder: nextSortOrder)
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

    @discardableResult
    private static func assign(_ label: LabelTag, to documents: [DocumentRecord]) -> Bool {
        documents.reduce(false) { didChange, document in
            assign(label, to: document) || didChange
        }
    }

    @discardableResult
    private static func remove(_ label: LabelTag, from documents: [DocumentRecord]) -> Bool {
        documents.reduce(false) { didChange, document in
            let originalCount = document.labels.count
            document.labels.removeAll { $0.persistentModelID == label.persistentModelID }
            return document.labels.count != originalCount || didChange
        }
    }
}

private struct LabelMutationResult {
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