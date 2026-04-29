import Foundation
import SwiftData

enum ManageLabelsUseCase {
    @discardableResult
    static func createLabel(
        named name: String,
        color: LabelColor,
        icon: String? = nil,
        unitSymbol: String? = nil,
        groupID: UUID? = nil,
        using modelContext: ModelContext
    ) throws -> LabelTag {
        let result = try createOrFetchLabel(
            named: name,
            color: color,
            icon: icon,
            unitSymbol: unitSymbol,
            groupID: groupID,
            requiresUnitMatch: true,
            using: modelContext
        )

        if result.didCreateLabel {
            try modelContext.save()
        }

        return result.label
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
            try ManageLabelValuesUseCase.deleteValues(for: documents, label: label, using: modelContext)
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
            try reconcileUnitsForMerge(
                sourceUnit: label.unitSymbol,
                destination: existingLabel,
                requestedSourceUnit: label.unitSymbol
            )
            try ManageLabelValuesUseCase.mergeValues(
                fromLabelID: label.id,
                intoLabelID: existingLabel.id,
                using: modelContext
            )
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

        try ManageLabelValuesUseCase.deleteValues(forLabelID: label.id, using: modelContext)
        modelContext.delete(label)
        try modelContext.save()
    }

    static func assignToGroup(_ label: LabelTag, groupID: UUID?, using modelContext: ModelContext) throws {
        label.groupID = groupID
        try modelContext.save()
    }

    static func update(
        _ label: LabelTag,
        name: String,
        color: LabelColor,
        icon: String?,
        unitSymbol: String? = nil,
        groupID: UUID?,
        using modelContext: ModelContext
    ) throws {
        let normalizedName = try normalizedLabelName(from: name)
        let normalizedUnit = try ManageLabelValuesUseCase.normalizedUnitSymbol(from: unitSymbol)

        do {
            let targetLabel: LabelTag
            let shouldApplyUnitToTarget: Bool
            if let existing = try existingLabel(named: normalizedName, using: modelContext),
               existing.persistentModelID != label.persistentModelID {
                try reconcileUnitsForMerge(
                    sourceUnit: label.unitSymbol,
                    destination: existing,
                    requestedSourceUnit: normalizedUnit
                )
                shouldApplyUnitToTarget = !(label.unitSymbol == nil && normalizedUnit == nil && existing.unitSymbol != nil)
                if label.unitSymbol != nil, normalizedUnit == nil {
                    try ManageLabelValuesUseCase.deleteValues(forLabelID: label.id, using: modelContext)
                }
                try ManageLabelValuesUseCase.mergeValues(
                    fromLabelID: label.id,
                    intoLabelID: existing.id,
                    using: modelContext
                )
                for document in Array(label.documents) {
                    _ = assign(existing, to: document)
                    document.labels.removeAll { $0.persistentModelID == label.persistentModelID }
                }
                modelContext.delete(label)
                targetLabel = existing
            } else {
                label.name = normalizedName
                targetLabel = label
                shouldApplyUnitToTarget = true
            }

            targetLabel.labelColor = color
            targetLabel.icon = icon
            if shouldApplyUnitToTarget, targetLabel.unitSymbol != nil, normalizedUnit == nil {
                try ManageLabelValuesUseCase.deleteValues(forLabelID: targetLabel.id, using: modelContext)
            }
            if shouldApplyUnitToTarget {
                targetLabel.unitSymbol = normalizedUnit
            }
            targetLabel.groupID = groupID

            try modelContext.save()
        } catch {
            modelContext.rollback()
            throw error
        }
    }

    static func changeColor(of label: LabelTag, to color: LabelColor, using modelContext: ModelContext) throws {
        label.labelColor = color
        try modelContext.save()
    }

    @discardableResult
    static func createOrReuseLabelForAssignment(
        named name: String,
        color: LabelColor,
        icon: String? = nil,
        groupID: UUID? = nil,
        using modelContext: ModelContext
    ) throws -> LabelTag {
        let result = try createOrFetchLabel(
            named: name,
            color: color,
            icon: icon,
            groupID: groupID,
            using: modelContext
        )

        if result.didCreateLabel {
            try modelContext.save()
        }

        return result.label
    }

    static func changeIcon(of label: LabelTag, to icon: String?, using modelContext: ModelContext) throws {
        label.icon = icon
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

    private static func createOrFetchLabel(
        named name: String,
        color: LabelColor = .blue,
        icon: String? = nil,
        unitSymbol: String? = nil,
        groupID: UUID? = nil,
        requiresUnitMatch: Bool = false,
        using modelContext: ModelContext
    ) throws -> LabelMutationResult {
        let normalizedName = try normalizedLabelName(from: name)
        let normalizedUnit = try ManageLabelValuesUseCase.normalizedUnitSymbol(from: unitSymbol)

        let descriptor = FetchDescriptor<LabelTag>(sortBy: [SortDescriptor(\.sortOrder, order: .forward)])
        let allLabels = try modelContext.fetch(descriptor)

        if let existingLabel = allLabels.first(where: {
            $0.name.compare(normalizedName, options: [.caseInsensitive, .diacriticInsensitive]) == .orderedSame
        }) {
            if requiresUnitMatch, existingLabel.unitSymbol != normalizedUnit {
                throw LabelValidationError.duplicateNameWithDifferentUnit
            }
            return LabelMutationResult(label: existingLabel, didCreateLabel: false)
        }

        let nextSortOrder = (allLabels.map(\.sortOrder).max() ?? -1) + 1
        let label = LabelTag(
            name: normalizedName,
            unitSymbol: normalizedUnit,
            colorName: color.rawValue,
            sortOrder: nextSortOrder,
            groupID: groupID
        )
        label.icon = icon
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
        try StringNormalization.nonEmptyCollapsedWhitespace(rawName, emptyError: LabelValidationError.emptyName)
    }

    @discardableResult
    private static func assign(_ label: LabelTag, to document: DocumentRecord) -> Bool {
        guard !document.labels.contains(where: { $0.persistentModelID == label.persistentModelID }) else {
            return false
        }

        document.labels.append(label)
        return true
    }

    @discardableResult
    private static func assign(_ label: LabelTag, to documents: [DocumentRecord]) -> Bool {
        documents.reduce(false) { didChange, document in
            let changed = assign(label, to: document)
            if changed, document.labels.count > 1 {
                document.labels.sort {
                    $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
                }
            }
            return changed || didChange
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

    private static func reconcileUnitsForMerge(
        sourceUnit: String?,
        destination: LabelTag,
        requestedSourceUnit: String?
    ) throws {
        let effectiveSourceUnit = requestedSourceUnit
        guard let effectiveSourceUnit else {
            if destination.unitSymbol != nil, sourceUnit != nil {
                throw LabelValidationError.incompatibleUnitsForMerge
            }
            return
        }

        if let destinationUnit = destination.unitSymbol, destinationUnit != effectiveSourceUnit {
            throw LabelValidationError.incompatibleUnitsForMerge
        }

        if destination.unitSymbol == nil, sourceUnit != nil || requestedSourceUnit != nil {
            destination.unitSymbol = effectiveSourceUnit
        }
    }
}

extension ManageLabelsUseCase {
    static func valuesAffectedByClearingUnit(for label: LabelTag, using modelContext: ModelContext) throws -> Int {
        try ManageLabelValuesUseCase.documentCountWithValues(forLabelID: label.id, using: modelContext)
    }
}

private struct LabelMutationResult {
    let label: LabelTag
    let didCreateLabel: Bool
}

enum LabelValidationError: LocalizedError {
    case emptyName
    case unitTooLong
    case incompatibleUnitsForMerge
    case duplicateNameWithDifferentUnit

    var errorDescription: String? {
        switch self {
        case .emptyName:
            return "Labels need a name."
        case .unitTooLong:
            return "Label units must be 12 characters or fewer."
        case .incompatibleUnitsForMerge:
            return "Labels with different units cannot be merged."
        case .duplicateNameWithDifferentUnit:
            return "A label with this name already exists with a different unit."
        }
    }
}

enum LabelValueStatisticsScope: String, CaseIterable, Identifiable, Sendable {
    case filtered
    case selection

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .filtered: "Filtered"
        case .selection: "Selection"
        }
    }
}

struct LabelValueStatistics: Sendable, Equatable {
    let labelID: UUID
    let labelName: String
    let unitSymbol: String
    let scope: LabelValueStatisticsScope
    let availableScopes: Set<LabelValueStatisticsScope>
    let scopeDocumentCount: Int
    let valuedDocumentCount: Int
    let missingValueCount: Int
    let sum: Decimal?
    let average: Decimal?
    let minimum: Decimal?
    let maximum: Decimal?
    let median: Decimal?
}

struct LabelValueStatisticsSummary: Sendable, Equatable {
    let filtered: LabelValueStatistics
    let selection: LabelValueStatistics
}

struct LabelValueSnapshot: Sendable, Equatable {
    let documentID: UUID
    let labelID: UUID
    let decimalString: String
}

enum ManageLabelValuesUseCase {
    private static let maxUnitLength = 12
    private static let maxTotalDigits = 30
    private static let maxFractionDigits = 6

    static func normalizedUnitSymbol(from rawUnit: String?) throws -> String? {
        let normalized = StringNormalization.collapsedWhitespace(rawUnit ?? "")
        guard !normalized.isEmpty else { return nil }
        guard normalized.count <= maxUnitLength else {
            throw LabelValidationError.unitTooLong
        }
        return normalized
    }

    static func normalizedDecimalString(from rawValue: String, locale: Locale = .current) throws -> String {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            throw LabelValueValidationError.emptyValue
        }
        guard !trimmed.localizedCaseInsensitiveContains("nan"),
              !trimmed.localizedCaseInsensitiveContains("inf"),
              !trimmed.contains("e"),
              !trimmed.contains("E") else {
            throw LabelValueValidationError.invalidValue
        }

        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.generatesDecimalNumbers = true

        let decimalSeparator = locale.decimalSeparator ?? "."
        let groupingSeparator = locale.groupingSeparator ?? ","
        let fallback = trimmed
            .replacingOccurrences(of: groupingSeparator, with: "")
            .replacingOccurrences(of: decimalSeparator, with: ".")
        let decimal = (formatter.number(from: trimmed) as? NSDecimalNumber)?.decimalValue ?? Decimal(string: fallback, locale: Locale(identifier: "en_US_POSIX"))

        guard let decimal else {
            throw LabelValueValidationError.invalidValue
        }

        let normalized = NSDecimalNumber(decimal: decimal).stringValue
        try validateDecimalString(normalized)
        return normalized
    }

    static func decimal(from normalizedString: String) -> Decimal? {
        Decimal(string: normalizedString, locale: Locale(identifier: "en_US_POSIX"))
    }

    static func formattedValue(_ value: Decimal, unitSymbol: String) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.maximumFractionDigits = maxFractionDigits
        formatter.minimumFractionDigits = 0
        let number = NSDecimalNumber(decimal: value)
        let formatted = formatter.string(from: number) ?? number.stringValue
        return "\(formatted) \(unitSymbol)"
    }

    static func setValue(
        _ rawValue: String,
        for document: DocumentRecord,
        label: LabelTag,
        using modelContext: ModelContext,
        locale: Locale = .current
    ) throws {
        let normalized = try normalizedDecimalString(from: rawValue, locale: locale)
        try setNormalizedValue(normalized, documentID: document.id, labelID: label.id, using: modelContext)
    }

    static func clearValue(for document: DocumentRecord, label: LabelTag, using modelContext: ModelContext) throws {
        try deleteValues(documentID: document.id, labelID: label.id, using: modelContext)
        try modelContext.save()
    }

    static func normalizedValue(for documentID: UUID, labelID: UUID, in values: [DocumentLabelValue]) -> String? {
        values.first { $0.documentID == documentID && $0.labelID == labelID }?.decimalString
    }

    static func snapshots(from values: [DocumentLabelValue]) -> [LabelValueSnapshot] {
        values.map {
            LabelValueSnapshot(documentID: $0.documentID, labelID: $0.labelID, decimalString: $0.decimalString)
        }
    }

    static func statistics(
        labelID: UUID,
        labelName: String,
        unitSymbol: String,
        scope: LabelValueStatisticsScope,
        availableScopes: Set<LabelValueStatisticsScope>,
        documentIDs: [UUID],
        values: [LabelValueSnapshot]
    ) -> LabelValueStatistics {
        let documentIDSet = Set(documentIDs)
        let decimals = values.compactMap { value -> Decimal? in
            guard value.labelID == labelID, documentIDSet.contains(value.documentID) else { return nil }
            return decimal(from: value.decimalString)
        }
        .sorted()

        let sum = decimals.reduce(Decimal(0), +)
        let count = decimals.count
        let median: Decimal?
        if count == 0 {
            median = nil
        } else if count.isMultiple(of: 2) {
            median = (decimals[count / 2 - 1] + decimals[count / 2]) / Decimal(2)
        } else {
            median = decimals[count / 2]
        }

        return LabelValueStatistics(
            labelID: labelID,
            labelName: labelName,
            unitSymbol: unitSymbol,
            scope: scope,
            availableScopes: availableScopes,
            scopeDocumentCount: documentIDs.count,
            valuedDocumentCount: count,
            missingValueCount: max(documentIDs.count - count, 0),
            sum: count > 0 ? sum : nil,
            average: count > 0 ? sum / Decimal(count) : nil,
            minimum: decimals.first,
            maximum: decimals.last,
            median: median
        )
    }

    static func documentCountWithValues(forLabelID labelID: UUID, using modelContext: ModelContext) throws -> Int {
        let values = try modelContext.fetch(FetchDescriptor<DocumentLabelValue>())
        return Set(values.filter { $0.labelID == labelID }.map(\.documentID)).count
    }

    static func deleteValues(forLabelID labelID: UUID, using modelContext: ModelContext) throws {
        let values = try modelContext.fetch(FetchDescriptor<DocumentLabelValue>())
        for value in values where value.labelID == labelID {
            modelContext.delete(value)
        }
    }

    static func deleteValues(forDocumentIDs documentIDs: Set<UUID>, using modelContext: ModelContext) throws {
        guard !documentIDs.isEmpty else { return }
        let values = try modelContext.fetch(FetchDescriptor<DocumentLabelValue>())
        for value in values where documentIDs.contains(value.documentID) {
            modelContext.delete(value)
        }
    }

    static func deleteValues(documentID: UUID, labelID: UUID, using modelContext: ModelContext) throws {
        let values = try modelContext.fetch(FetchDescriptor<DocumentLabelValue>())
        for value in values where value.documentID == documentID && value.labelID == labelID {
            modelContext.delete(value)
        }
    }

    static func deleteValues(for documents: [DocumentRecord], label: LabelTag, using modelContext: ModelContext) throws {
        let documentIDs = Set(documents.map(\.id))
        let values = try modelContext.fetch(FetchDescriptor<DocumentLabelValue>())
        for value in values where value.labelID == label.id && documentIDs.contains(value.documentID) {
            modelContext.delete(value)
        }
    }

    static func mergeValues(fromLabelID sourceLabelID: UUID, intoLabelID destinationLabelID: UUID, using modelContext: ModelContext) throws {
        let values = try modelContext.fetch(FetchDescriptor<DocumentLabelValue>())
        let destinationDocumentIDs = Set(values.filter { $0.labelID == destinationLabelID }.map(\.documentID))
        for value in values where value.labelID == sourceLabelID {
            if destinationDocumentIDs.contains(value.documentID) {
                modelContext.delete(value)
            } else {
                value.labelID = destinationLabelID
                value.updatedAt = .now
            }
        }
    }

    static func pruneStaleValues(validDocumentIDs: Set<UUID>, validLabelIDs: Set<UUID>, using modelContext: ModelContext) throws {
        let values = try modelContext.fetch(FetchDescriptor<DocumentLabelValue>())
        var seenPairs: Set<String> = []
        for value in values {
            let pairKey = "\(value.documentID.uuidString)|\(value.labelID.uuidString)"
            if !validDocumentIDs.contains(value.documentID)
                || !validLabelIDs.contains(value.labelID)
                || seenPairs.contains(pairKey) {
                modelContext.delete(value)
            } else {
                seenPairs.insert(pairKey)
            }
        }
    }

    private static func setNormalizedValue(_ normalized: String, documentID: UUID, labelID: UUID, using modelContext: ModelContext) throws {
        var values = try modelContext.fetch(FetchDescriptor<DocumentLabelValue>())
            .filter { $0.documentID == documentID && $0.labelID == labelID }
        if let first = values.first {
            first.decimalString = normalized
            first.updatedAt = .now
            values.removeFirst()
            for duplicate in values {
                modelContext.delete(duplicate)
            }
        } else {
            modelContext.insert(DocumentLabelValue(documentID: documentID, labelID: labelID, decimalString: normalized))
        }
        try modelContext.save()
    }

    private static func validateDecimalString(_ value: String) throws {
        let trimmedSign = value.trimmingCharacters(in: CharacterSet(charactersIn: "-+"))
        let parts = trimmedSign.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count <= 2 else {
            throw LabelValueValidationError.invalidValue
        }
        let digitCount = trimmedSign.filter(\.isNumber).count
        let fractionCount = parts.count == 2 ? parts[1].filter(\.isNumber).count : 0
        guard digitCount > 0, digitCount <= maxTotalDigits, fractionCount <= maxFractionDigits else {
            throw LabelValueValidationError.invalidValue
        }
    }
}

enum LabelValueValidationError: LocalizedError {
    case emptyValue
    case invalidValue

    var errorDescription: String? {
        switch self {
        case .emptyValue:
            return "Enter a value or clear the field."
        case .invalidValue:
            return "Enter a valid decimal value with up to 30 digits and 6 decimal places."
        }
    }
}
