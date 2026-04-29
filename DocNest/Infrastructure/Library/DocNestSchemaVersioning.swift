import Foundation
import SwiftData

// MARK: - Schema V1
// Original schema — all models as they existed before the ocrCompleted field was added.

enum DocNestSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [DocumentRecord.self, LabelTag.self, SmartFolder.self, LabelGroup.self]
    }

    @Model
    final class DocumentRecord {
        var id: UUID
        var originalFileName: String
        var title: String
        var sourceCreatedAt: Date?
        var importedAt: Date
        var pageCount: Int
        var fileSize: Int64
        var contentHash: String
        var storedFilePath: String?
        var fullText: String?
        var trashedAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \LabelTag.documents)
        var labels: [LabelTag] = []

        init(
            id: UUID = UUID(),
            originalFileName: String,
            title: String,
            sourceCreatedAt: Date? = nil,
            importedAt: Date,
            pageCount: Int,
            fileSize: Int64 = 0,
            contentHash: String = "",
            storedFilePath: String? = nil,
            trashedAt: Date? = nil,
            labels: [LabelTag] = []
        ) {
            self.id = id
            self.originalFileName = originalFileName
            self.title = title
            self.sourceCreatedAt = sourceCreatedAt
            self.importedAt = importedAt
            self.pageCount = pageCount
            self.fileSize = fileSize
            self.contentHash = contentHash
            self.storedFilePath = storedFilePath
            self.trashedAt = trashedAt
            self.labels = labels
        }
    }

    @Model
    final class LabelTag {
        var id: UUID
        var name: String
        var colorName: String
        var icon: String?
        var sortOrder: Int
        var groupID: UUID?
        var documents: [DocumentRecord] = []

        init(id: UUID = UUID(), name: String, colorName: String = "blue", sortOrder: Int = 0, groupID: UUID? = nil) {
            self.id = id
            self.name = name
            self.colorName = colorName
            self.sortOrder = sortOrder
            self.groupID = groupID
        }
    }

    @Model
    final class SmartFolder {
        var id: UUID
        var name: String
        var icon: String?
        var labelIDs: [UUID]
        var sortOrder: Int

        init(id: UUID = UUID(), name: String, icon: String? = nil, labelIDs: [UUID] = [], sortOrder: Int = 0) {
            self.id = id
            self.name = name
            self.icon = icon
            self.labelIDs = labelIDs
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class LabelGroup {
        var id: UUID
        var name: String
        var sortOrder: Int

        init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
        }
    }
}

// MARK: - Schema V2
// Adds ocrCompleted: Bool to DocumentRecord.

enum DocNestSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [DocumentRecord.self, LabelTag.self, SmartFolder.self, LabelGroup.self]
    }

    @Model
    final class DocumentRecord {
        var id: UUID
        var originalFileName: String
        var title: String
        var sourceCreatedAt: Date?
        var importedAt: Date
        var pageCount: Int
        var fileSize: Int64
        var contentHash: String
        var storedFilePath: String?
        var fullText: String?
        var ocrCompleted: Bool = false
        var trashedAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \LabelTag.documents)
        var labels: [LabelTag] = []

        init(
            id: UUID = UUID(),
            originalFileName: String,
            title: String,
            sourceCreatedAt: Date? = nil,
            importedAt: Date,
            pageCount: Int,
            fileSize: Int64 = 0,
            contentHash: String = "",
            storedFilePath: String? = nil,
            trashedAt: Date? = nil,
            labels: [LabelTag] = []
        ) {
            self.id = id
            self.originalFileName = originalFileName
            self.title = title
            self.sourceCreatedAt = sourceCreatedAt
            self.importedAt = importedAt
            self.pageCount = pageCount
            self.fileSize = fileSize
            self.contentHash = contentHash
            self.storedFilePath = storedFilePath
            self.trashedAt = trashedAt
            self.labels = labels
        }
    }

    @Model
    final class LabelTag {
        var id: UUID
        var name: String
        var colorName: String
        var icon: String?
        var sortOrder: Int
        var groupID: UUID?
        var documents: [DocumentRecord] = []

        init(id: UUID = UUID(), name: String, colorName: String = "blue", sortOrder: Int = 0, groupID: UUID? = nil) {
            self.id = id
            self.name = name
            self.colorName = colorName
            self.sortOrder = sortOrder
            self.groupID = groupID
        }
    }

    @Model
    final class SmartFolder {
        var id: UUID
        var name: String
        var icon: String?
        var labelIDs: [UUID]
        var sortOrder: Int

        init(id: UUID = UUID(), name: String, icon: String? = nil, labelIDs: [UUID] = [], sortOrder: Int = 0) {
            self.id = id
            self.name = name
            self.icon = icon
            self.labelIDs = labelIDs
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class LabelGroup {
        var id: UUID
        var name: String
        var sortOrder: Int

        init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
        }
    }
}

// MARK: - Schema V3
// Adds WatchFolder entity.
// All models are defined as inner types so the version checksum is self-contained
// and does not depend on top-level types that may change in later schema versions.

enum DocNestSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [DocumentRecord.self, LabelTag.self, SmartFolder.self, LabelGroup.self, WatchFolder.self]
    }

    @Model
    final class DocumentRecord {
        var id: UUID
        var originalFileName: String
        var title: String
        var sourceCreatedAt: Date?
        var importedAt: Date
        var pageCount: Int
        var fileSize: Int64
        var contentHash: String
        var storedFilePath: String?
        var fullText: String?
        var ocrCompleted: Bool = false
        var trashedAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \LabelTag.documents)
        var labels: [LabelTag] = []

        init(
            id: UUID = UUID(),
            originalFileName: String,
            title: String,
            sourceCreatedAt: Date? = nil,
            importedAt: Date,
            pageCount: Int,
            fileSize: Int64 = 0,
            contentHash: String = "",
            storedFilePath: String? = nil,
            trashedAt: Date? = nil,
            labels: [LabelTag] = []
        ) {
            self.id = id
            self.originalFileName = originalFileName
            self.title = title
            self.sourceCreatedAt = sourceCreatedAt
            self.importedAt = importedAt
            self.pageCount = pageCount
            self.fileSize = fileSize
            self.contentHash = contentHash
            self.storedFilePath = storedFilePath
            self.trashedAt = trashedAt
            self.labels = labels
        }
    }

    @Model
    final class LabelTag {
        var id: UUID
        var name: String
        var colorName: String
        var icon: String?
        var sortOrder: Int
        var groupID: UUID?
        var documents: [DocumentRecord] = []

        init(id: UUID = UUID(), name: String, colorName: String = "blue", sortOrder: Int = 0, groupID: UUID? = nil) {
            self.id = id
            self.name = name
            self.colorName = colorName
            self.sortOrder = sortOrder
            self.groupID = groupID
        }
    }

    @Model
    final class SmartFolder {
        var id: UUID
        var name: String
        var icon: String?
        var labelIDs: [UUID]
        var sortOrder: Int

        init(id: UUID = UUID(), name: String, icon: String? = nil, labelIDs: [UUID] = [], sortOrder: Int = 0) {
            self.id = id
            self.name = name
            self.icon = icon
            self.labelIDs = labelIDs
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class LabelGroup {
        var id: UUID
        var name: String
        var sortOrder: Int

        init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class WatchFolder {
        var id: UUID
        var name: String
        var icon: String?
        var folderPath: String
        var isEnabled: Bool
        var labelIDs: [UUID]
        var sortOrder: Int

        init(
            id: UUID = UUID(),
            name: String,
            icon: String? = nil,
            folderPath: String,
            isEnabled: Bool = true,
            labelIDs: [UUID] = [],
            sortOrder: Int = 0
        ) {
            self.id = id
            self.name = name
            self.icon = icon
            self.folderPath = folderPath
            self.isEnabled = isEnabled
            self.labelIDs = labelIDs
            self.sortOrder = sortOrder
        }
    }
}

// MARK: - Schema V4
// Renames sourceCreatedAt → documentDate on DocumentRecord (lightweight via @Attribute(originalName:)).

enum DocNestSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [
            DocNestSchemaV4.DocumentRecord.self,
            DocNestSchemaV4.LabelTag.self,
            DocNestSchemaV4.SmartFolder.self,
            DocNestSchemaV4.LabelGroup.self,
            DocNestSchemaV4.WatchFolder.self
        ]
    }

    @Model
    final class DocumentRecord {
        var id: UUID
        var originalFileName: String
        var title: String
        @Attribute(originalName: "sourceCreatedAt") var documentDate: Date?
        var importedAt: Date
        var pageCount: Int
        var fileSize: Int64
        var contentHash: String
        var storedFilePath: String?
        var fullText: String?
        var ocrCompleted: Bool = false
        var trashedAt: Date?

        @Relationship(deleteRule: .nullify, inverse: \LabelTag.documents)
        var labels: [LabelTag] = []

        init(
            id: UUID = UUID(),
            originalFileName: String,
            title: String,
            documentDate: Date? = nil,
            importedAt: Date,
            pageCount: Int,
            fileSize: Int64 = 0,
            contentHash: String = "",
            storedFilePath: String? = nil,
            trashedAt: Date? = nil,
            labels: [LabelTag] = []
        ) {
            self.id = id
            self.originalFileName = originalFileName
            self.title = title
            self.documentDate = documentDate
            self.importedAt = importedAt
            self.pageCount = pageCount
            self.fileSize = fileSize
            self.contentHash = contentHash
            self.storedFilePath = storedFilePath
            self.trashedAt = trashedAt
            self.labels = labels
        }
    }

    @Model
    final class LabelTag {
        var id: UUID
        var name: String
        var colorName: String
        var icon: String?
        var sortOrder: Int
        var groupID: UUID?
        var documents: [DocumentRecord] = []

        init(id: UUID = UUID(), name: String, colorName: String = "blue", sortOrder: Int = 0, groupID: UUID? = nil) {
            self.id = id
            self.name = name
            self.colorName = colorName
            self.sortOrder = sortOrder
            self.groupID = groupID
        }
    }

    @Model
    final class SmartFolder {
        var id: UUID
        var name: String
        var icon: String?
        var labelIDs: [UUID]
        var sortOrder: Int

        init(id: UUID = UUID(), name: String, icon: String? = nil, labelIDs: [UUID] = [], sortOrder: Int = 0) {
            self.id = id
            self.name = name
            self.icon = icon
            self.labelIDs = labelIDs
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class LabelGroup {
        var id: UUID
        var name: String
        var sortOrder: Int

        init(id: UUID = UUID(), name: String, sortOrder: Int = 0) {
            self.id = id
            self.name = name
            self.sortOrder = sortOrder
        }
    }

    @Model
    final class WatchFolder {
        var id: UUID
        var name: String
        var icon: String?
        var folderPath: String
        var isEnabled: Bool
        var labelIDs: [UUID]
        var sortOrder: Int

        init(
            id: UUID = UUID(),
            name: String,
            icon: String? = nil,
            folderPath: String,
            isEnabled: Bool = true,
            labelIDs: [UUID] = [],
            sortOrder: Int = 0
        ) {
            self.id = id
            self.name = name
            self.icon = icon
            self.folderPath = folderPath
            self.isEnabled = isEnabled
            self.labelIDs = labelIDs
            self.sortOrder = sortOrder
        }
    }
}

// MARK: - Schema V5
// Adds optional label units and document-label value metadata. V5 references
// top-level models so @Query descriptors remain compatible with current app code.

enum DocNestSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [DocumentRecord.self, LabelTag.self, SmartFolder.self, LabelGroup.self, WatchFolder.self, DocumentLabelValue.self]
    }
}

// MARK: - Migration Plan

enum DocNestMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [DocNestSchemaV1.self, DocNestSchemaV2.self, DocNestSchemaV3.self, DocNestSchemaV4.self, DocNestSchemaV5.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: DocNestSchemaV1.self,
        toVersion: DocNestSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: DocNestSchemaV2.self,
        toVersion: DocNestSchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: DocNestSchemaV3.self,
        toVersion: DocNestSchemaV4.self
    )

    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: DocNestSchemaV4.self,
        toVersion: DocNestSchemaV5.self
    )
}
