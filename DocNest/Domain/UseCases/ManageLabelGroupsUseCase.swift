import Foundation
import SwiftData

enum ManageLabelGroupsUseCase {
    @discardableResult
    static func create(named name: String, using modelContext: ModelContext) throws -> LabelGroup {
        let trimmedName = try normalizedName(from: name)

        let descriptor = FetchDescriptor<LabelGroup>(sortBy: [SortDescriptor(\.sortOrder)])
        let existing = try modelContext.fetch(descriptor)
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1

        let group = LabelGroup(name: trimmedName, sortOrder: nextOrder)
        modelContext.insert(group)
        try modelContext.save()
        return group
    }

    static func rename(_ group: LabelGroup, to newName: String, using modelContext: ModelContext) throws {
        group.name = try normalizedName(from: newName)
        try modelContext.save()
    }

    static func delete(_ group: LabelGroup, using modelContext: ModelContext) throws {
        let descriptor = FetchDescriptor<LabelTag>()
        let labels = try modelContext.fetch(descriptor)
        for label in labels where label.groupID == group.id {
            label.groupID = nil
        }

        modelContext.delete(group)
        try modelContext.save()
    }

    static func reorder(from source: IndexSet, to destination: Int, groups: [LabelGroup], using modelContext: ModelContext) throws {
        var reordered = groups
        reordered.move(fromOffsets: source, toOffset: destination)

        for (index, group) in reordered.enumerated() {
            group.sortOrder = index
        }

        try modelContext.save()
    }

    private static func normalizedName(from rawName: String) throws -> String {
        let collapsed = rawName
            .components(separatedBy: .whitespacesAndNewlines)
            .filter { !$0.isEmpty }
            .joined(separator: " ")

        guard !collapsed.isEmpty else {
            throw LabelGroupValidationError.emptyName
        }

        return collapsed
    }
}

enum LabelGroupValidationError: LocalizedError {
    case emptyName

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Label groups need a name."
        }
    }
}
