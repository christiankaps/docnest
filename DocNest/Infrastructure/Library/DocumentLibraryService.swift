import AppKit
import CryptoKit
import Foundation
import PDFKit
import SwiftData
import UniformTypeIdentifiers

extension UTType {
    static let docNestLibrary = UTType("com.kaps.docnest.library")!
}

struct DocumentLibraryManifest: Codable {
    let formatVersion: Int
    let createdAt: Date
    let libraryID: UUID
    let storageMode: LibraryStorageMode
    let sparsebundleRelativePath: String?
    let mountedVolumeName: String?
    let imageFileSystem: String?
    let imageFormatVersion: Int?

    init(
        formatVersion: Int,
        createdAt: Date,
        libraryID: UUID = UUID(),
        storageMode: LibraryStorageMode = .plainPackage,
        sparsebundleRelativePath: String? = nil,
        mountedVolumeName: String? = nil,
        imageFileSystem: String? = nil,
        imageFormatVersion: Int? = nil
    ) {
        self.formatVersion = formatVersion
        self.createdAt = createdAt
        self.libraryID = libraryID
        self.storageMode = storageMode
        self.sparsebundleRelativePath = sparsebundleRelativePath
        self.mountedVolumeName = mountedVolumeName
        self.imageFileSystem = imageFileSystem
        self.imageFormatVersion = imageFormatVersion
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        formatVersion = try container.decode(Int.self, forKey: .formatVersion)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        libraryID = try container.decodeIfPresent(UUID.self, forKey: .libraryID) ?? UUID()
        storageMode = try container.decodeIfPresent(LibraryStorageMode.self, forKey: .storageMode) ?? .plainPackage
        sparsebundleRelativePath = try container.decodeIfPresent(String.self, forKey: .sparsebundleRelativePath)
        mountedVolumeName = try container.decodeIfPresent(String.self, forKey: .mountedVolumeName)
        imageFileSystem = try container.decodeIfPresent(String.self, forKey: .imageFileSystem)
        imageFormatVersion = try container.decodeIfPresent(Int.self, forKey: .imageFormatVersion)
    }
}

enum LibraryStorageMode: String, Codable {
    case plainPackage
    case encryptedSparsebundle
}

struct LibraryMigrationResult: Codable {
    let wasMigrated: Bool
    let fromFormatVersion: Int
    let toFormatVersion: Int

    static func none(currentVersion: Int) -> LibraryMigrationResult {
        LibraryMigrationResult(
            wasMigrated: false,
            fromFormatVersion: currentVersion,
            toFormatVersion: currentVersion
        )
    }
}

struct LibraryRepairAction: Codable, Identifiable {
    enum Kind: String, Codable {
        case createdDirectory
        case recreatedManifest
        case backfilledContentHash
        case backfilledFileSize
        case backfilledPageCount
    }

    let id: UUID
    let kind: Kind
    let target: String
    let message: String

    init(kind: Kind, target: String, message: String) {
        self.id = UUID()
        self.kind = kind
        self.target = target
        self.message = message
    }
}

struct LibraryRepairResult: Codable {
    let performedRepair: Bool
    let actions: [LibraryRepairAction]

    static let none = LibraryRepairResult(performedRepair: false, actions: [])
}

struct LibraryIntegrityIssue: Codable, Identifiable {
    enum Severity: String, Codable {
        case warning
        case error
    }

    let id: UUID
    let severity: Severity
    let code: String
    let message: String

    init(severity: Severity, code: String, message: String) {
        self.id = UUID()
        self.severity = severity
        self.code = code
        self.message = message
    }
}

struct LibraryIntegrityReport: Codable {
    let generatedAt: Date
    let libraryPath: String
    let manifestFormatVersion: Int
    let schemaVersion: String
    let migration: LibraryMigrationResult
    let repair: LibraryRepairResult
    let documentCount: Int
    let issues: [LibraryIntegrityIssue]

    var hasErrors: Bool {
        issues.contains { $0.severity == .error }
    }
}

struct LibraryLockFile: Codable {
    let hostname: String
    let pid: Int32
    let updatedAt: Date

    static let staleThreshold: TimeInterval = 60

    var isStale: Bool {
        Date().timeIntervalSince(updatedAt) > Self.staleThreshold
    }

    var ownerDescription: String {
        "\(hostname) (PID \(pid))"
    }
}

enum DocumentLibraryService {
    struct PasswordChangeResult {
        let keychainWarning: String?
    }

    struct EncryptedLibraryCreationResult {
        let libraryURL: URL
        let keychainWarning: String?
    }

    struct EncryptionConversionResult {
        let warning: String?
    }

    static let packageExtension = "docnestlibrary"
    static let currentFormatVersion = 2
    static let currentImageFormatVersion = 1

    struct MountedLibraryVolume: Equatable {
        let imageURL: URL
        let mountPointURL: URL
        let deviceEntry: String
        let ownedByCurrentSession: Bool
    }

    struct RuntimeLocations: Equatable {
        let packageURL: URL
        let dataRootURL: URL
        let mountedVolume: MountedLibraryVolume?
    }

    struct LibraryAccessSession {
        let packageURL: URL
        let dataRootURL: URL
        let startedAccessingSecurityScope: Bool
        let mountedVolume: MountedLibraryVolume?

        var url: URL {
            packageURL
        }
    }

    private static let persistedLibraryPathKey = "selectedLibraryPath"
    private static let persistedLibraryBookmarkKey = "selectedLibraryBookmark"
    private static let launchArgumentSelectedLibraryPath = "-selectedLibraryPath"
    private static let manifestFileName = "library.json"
    private static let lockFileName = ".lock"
    private static let integrityReportFileName = "integrity-report.json"
    private static let plainDataDirectories = [
        "Metadata",
        "Originals",
        "Previews",
        "Diagnostics"
    ]
    private static let encryptedOuterDirectories = [
        "Mount",
        "Diagnostics"
    ]
    private static let encryptedInnerDirectories = [
        "Metadata",
        "Originals",
        "Previews",
        "DiagnosticsPrivate"
    ]
    static let defaultSparsebundleRelativePath = "Mount/Library.sparsebundle"

    static func restorePersistedLibraryAccess() -> LibraryAccessSession? {
        if let launchArgumentLibraryURL = selectedLibraryURL(from: ProcessInfo.processInfo.arguments) {
            return accessLibrary(at: launchArgumentLibraryURL)
        }

        if let bookmarkData = UserDefaults.standard.data(forKey: persistedLibraryBookmarkKey) {
            var isStale = false
            do {
                let resolvedURL = try URL(
                    resolvingBookmarkData: bookmarkData,
                    options: [.withSecurityScope],
                    relativeTo: nil,
                    bookmarkDataIsStale: &isStale
                ).standardizedFileURL

                guard !isURLInTrash(resolvedURL) else {
                    persistLibraryURL(nil)
                    return nil
                }

                let session = accessLibrary(at: resolvedURL)
                if isStale {
                    persistLibraryURL(resolvedURL)
                }
                return session
            } catch {
                UserDefaults.standard.removeObject(forKey: persistedLibraryBookmarkKey)
            }
        }

        guard let path = UserDefaults.standard.string(forKey: persistedLibraryPathKey) else {
            return nil
        }

        let url = URL(fileURLWithPath: path).standardizedFileURL
        guard !isURLInTrash(url) else {
            persistLibraryURL(nil)
            return nil
        }

        return accessLibrary(at: url)
    }

    static func persistLibraryURL(_ url: URL?) {
        if let url {
            let standardizedURL = url.standardizedFileURL
            UserDefaults.standard.set(standardizedURL.path, forKey: persistedLibraryPathKey)

            if let bookmarkData = try? standardizedURL.bookmarkData(
                options: [.withSecurityScope],
                includingResourceValuesForKeys: nil,
                relativeTo: nil
            ) {
                UserDefaults.standard.set(bookmarkData, forKey: persistedLibraryBookmarkKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: persistedLibraryPathKey)
            UserDefaults.standard.removeObject(forKey: persistedLibraryBookmarkKey)
        }
    }

    static func accessLibrary(at url: URL) -> LibraryAccessSession {
        let standardizedURL = url.standardizedFileURL
        let startedAccessingSecurityScope = standardizedURL.startAccessingSecurityScopedResource()
        return LibraryAccessSession(
            packageURL: standardizedURL,
            dataRootURL: standardizedURL,
            startedAccessingSecurityScope: startedAccessingSecurityScope,
            mountedVolume: nil
        )
    }

    static func promptForExistingLibrary() -> URL? {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.docNestLibrary]
        panel.prompt = "Open Library"
        panel.message = "Choose an existing DocNest library."

        guard panel.runModal() == .OK else {
            return nil
        }

        return panel.url?.standardizedFileURL
    }

    static func promptForNewLibraryURL() -> URL? {
        let panel = NSSavePanel()
        panel.canCreateDirectories = true
        panel.nameFieldStringValue = "My Documents"
        panel.prompt = "Create Library"
        panel.message = "Choose where the new DocNest library should be created."
        panel.allowedContentTypes = [.docNestLibrary]
        panel.isExtensionHidden = true

        guard panel.runModal() == .OK, let url = panel.url else {
            return nil
        }

        return normalizedLibraryURL(from: url)
    }

    static func createLibrary(at url: URL) throws -> URL {
        let libraryURL = normalizedLibraryURL(from: url)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        try createDirectories(plainDataDirectories, in: libraryURL)
        try writeManifest(
            DocumentLibraryManifest(formatVersion: currentFormatVersion, createdAt: .now),
            for: libraryURL
        )

        return libraryURL
    }

    static func createEncryptedLibrary(
        at url: URL,
        password: String,
        savePasswordInKeychain: Bool
    ) throws -> EncryptedLibraryCreationResult {
        let libraryURL = normalizedLibraryURL(from: url)
        let volumeName = libraryURL.deletingPathExtension().lastPathComponent
        let manifest = DocumentLibraryManifest(
            formatVersion: currentFormatVersion,
            createdAt: .now,
            storageMode: .encryptedSparsebundle,
            sparsebundleRelativePath: defaultSparsebundleRelativePath,
            mountedVolumeName: volumeName,
            imageFileSystem: "APFS",
            imageFormatVersion: currentImageFormatVersion
        )

        do {
            try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)
            try createDirectories(encryptedOuterDirectories, in: libraryURL)

            let imageURL = sparsebundleURL(for: libraryURL, manifest: manifest)
            try LibraryDiskImageService.createEncryptedSparsebundle(
                at: imageURL,
                volumeName: volumeName,
                password: password
            )

            let attached = try LibraryDiskImageService.attachSparsebundle(at: imageURL, password: password)
            defer {
                try? LibraryDiskImageService.detach(attached)
            }

            try createDirectories(encryptedInnerDirectories, in: attached.mountPointURL)
            try writeManifest(manifest, for: libraryURL)
        } catch {
            try? FileManager.default.removeItem(at: libraryURL)
            throw error
        }

        do {
            if savePasswordInKeychain {
                try LibraryDiskImageService.savePasswordInKeychain(password, libraryID: manifest.libraryID)
            } else {
                try LibraryDiskImageService.deletePasswordFromKeychain(libraryID: manifest.libraryID)
            }
            return EncryptedLibraryCreationResult(libraryURL: libraryURL, keychainWarning: nil)
        } catch {
            return EncryptedLibraryCreationResult(
                libraryURL: libraryURL,
                keychainWarning: "The encrypted library was created successfully, but the Keychain entry could not be updated automatically."
            )
        }
    }

    static func convertLibraryToEncrypted(
        at url: URL,
        password: String,
        savePasswordInKeychain: Bool
    ) throws -> EncryptionConversionResult {
        let libraryURL = normalizedLibraryURL(from: url)
        let manifest = try readManifest(for: libraryURL)
        guard manifest.storageMode == .plainPackage else {
            return EncryptionConversionResult(warning: nil)
        }

        let updatedManifest = DocumentLibraryManifest(
            formatVersion: currentFormatVersion,
            createdAt: manifest.createdAt,
            libraryID: manifest.libraryID,
            storageMode: .encryptedSparsebundle,
            sparsebundleRelativePath: defaultSparsebundleRelativePath,
            mountedVolumeName: libraryURL.deletingPathExtension().lastPathComponent,
            imageFileSystem: "APFS",
            imageFormatVersion: currentImageFormatVersion
        )

        try createDirectories(encryptedOuterDirectories, in: libraryURL)
        let imageURL = sparsebundleURL(for: libraryURL, manifest: updatedManifest)
        try LibraryDiskImageService.createEncryptedSparsebundle(
            at: imageURL,
            volumeName: updatedManifest.mountedVolumeName ?? libraryURL.deletingPathExtension().lastPathComponent,
            password: password
        )

        let mounted = try LibraryDiskImageService.attachSparsebundle(at: imageURL, password: password)
        var cleanupWarning: String?
        do {
            try createDirectories(encryptedInnerDirectories, in: mounted.mountPointURL)
            try copyPlainLibraryContents(from: libraryURL, to: mounted.mountPointURL)
            try validateMountedDataRoot(at: mounted.mountPointURL)
            let stagedPayloads = try stagePlaintextPayloadsForRemoval(from: libraryURL)
            do {
                try writeManifest(updatedManifest, for: libraryURL)
            } catch {
                try restoreStagedPlaintextPayloads(stagedPayloads, to: libraryURL)
                throw error
            }
            do {
                try discardStagedPlaintextPayloads(stagedPayloads)
            } catch {
                cleanupWarning = "The library was converted successfully, but a temporary plaintext backup could not be deleted automatically."
            }
        } catch {
            try? LibraryDiskImageService.detach(mounted, force: true)
            try? FileManager.default.removeItem(at: imageURL)
            throw error
        }

        do {
            try LibraryDiskImageService.detach(mounted)
        } catch {
            cleanupWarning = combineWarnings(
                cleanupWarning,
                "The library was converted successfully, but DocNest could not detach the temporary encrypted volume cleanly."
            )
        }

        do {
            if savePasswordInKeychain {
                try LibraryDiskImageService.savePasswordInKeychain(password, libraryID: updatedManifest.libraryID)
            } else {
                try LibraryDiskImageService.deletePasswordFromKeychain(libraryID: updatedManifest.libraryID)
            }
            return EncryptionConversionResult(warning: cleanupWarning)
        } catch {
            return EncryptionConversionResult(
                warning: combineWarnings(
                    cleanupWarning,
                    "The library was converted successfully, but the Keychain entry could not be updated automatically."
                )
            )
        }
    }

    static func changeEncryptedLibraryPassword(
        at url: URL,
        currentPassword: String,
        newPassword: String,
        savePasswordInKeychain: Bool
    ) throws -> PasswordChangeResult {
        let libraryURL = normalizedLibraryURL(from: url)
        let manifest = try readManifest(for: libraryURL)
        guard manifest.storageMode == .encryptedSparsebundle else {
            return PasswordChangeResult(keychainWarning: nil)
        }

        let imageURL = sparsebundleURL(for: libraryURL, manifest: manifest)
        if try LibraryDiskImageService.findMountedVolume(for: imageURL) != nil {
            throw LibraryDiskImageService.Error.mountedElsewhere
        }

        try LibraryDiskImageService.changePassword(
            forSparsebundle: imageURL,
            currentPassword: currentPassword,
            newPassword: newPassword
        )

        do {
            if savePasswordInKeychain {
                try LibraryDiskImageService.savePasswordInKeychain(newPassword, libraryID: manifest.libraryID)
            } else {
                try LibraryDiskImageService.deletePasswordFromKeychain(libraryID: manifest.libraryID)
            }
            return PasswordChangeResult(keychainWarning: nil)
        } catch {
            return PasswordChangeResult(
                keychainWarning: "The library password was changed, but the Keychain entry could not be updated automatically."
            )
        }
    }

    static func repairLibraryPackageIfNeeded(at url: URL) throws -> LibraryRepairResult {
        let libraryURL = normalizedLibraryURL(from: url)
        var actions: [LibraryRepairAction] = []

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: libraryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        let manifest = try? readManifest(for: libraryURL)
        let requiredDirectories = manifest?.storageMode == .encryptedSparsebundle
            ? encryptedOuterDirectories
            : plainDataDirectories

        for directory in requiredDirectories {
            let directoryURL = libraryURL.appendingPathComponent(directory, isDirectory: true)
            if !FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory) || !isDirectory.boolValue {
                try FileManager.default.createDirectory(at: directoryURL, withIntermediateDirectories: true)
                actions.append(
                    LibraryRepairAction(
                        kind: .createdDirectory,
                        target: directory,
                        message: "Created missing \(directory) directory."
                    )
                )
            }
        }

        let manifestURL = primaryManifestURL(for: libraryURL)
        if !FileManager.default.fileExists(atPath: manifestURL.path) {
            let manifest = try legacyOrDefaultManifest(for: libraryURL)
            try writeManifest(manifest, for: libraryURL)
            actions.append(
                LibraryRepairAction(
                    kind: .recreatedManifest,
                    target: manifestFileName,
                    message: "Recreated missing library manifest."
                )
            )
        }

        return LibraryRepairResult(performedRepair: !actions.isEmpty, actions: actions)
    }

    static func migrateLibraryIfNeeded(at libraryURL: URL, manifest: DocumentLibraryManifest) throws -> LibraryMigrationResult {
        guard manifest.formatVersion < currentFormatVersion else {
            return .none(currentVersion: manifest.formatVersion)
        }

        let updatedManifest = DocumentLibraryManifest(
            formatVersion: currentFormatVersion,
            createdAt: manifest.createdAt,
            libraryID: manifest.libraryID,
            storageMode: manifest.storageMode,
            sparsebundleRelativePath: manifest.sparsebundleRelativePath ?? (manifest.storageMode == .encryptedSparsebundle ? defaultSparsebundleRelativePath : nil),
            mountedVolumeName: manifest.mountedVolumeName,
            imageFileSystem: manifest.imageFileSystem,
            imageFormatVersion: manifest.imageFormatVersion ?? (manifest.storageMode == .encryptedSparsebundle ? currentImageFormatVersion : nil)
        )
        try writeManifest(updatedManifest, for: libraryURL)

        return LibraryMigrationResult(
            wasMigrated: true,
            fromFormatVersion: manifest.formatVersion,
            toFormatVersion: currentFormatVersion
        )
    }

    static func validateLibrary(at url: URL) throws -> (URL, DocumentLibraryManifest) {
        let libraryURL = url.standardizedFileURL
        var isDirectory: ObjCBool = false

        guard FileManager.default.fileExists(atPath: libraryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

        let manifest = try readManifest(for: libraryURL)
        let requiredDirectories = manifest.storageMode == .encryptedSparsebundle
            ? encryptedOuterDirectories
            : plainDataDirectories

        for directory in requiredDirectories {
            let directoryURL = libraryURL.appendingPathComponent(directory, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ValidationError.missingDirectory(directory)
            }
        }

        if manifest.storageMode == .encryptedSparsebundle {
            let imageURL = sparsebundleURL(for: libraryURL, manifest: manifest)
            guard FileManager.default.fileExists(atPath: imageURL.path) else {
                throw ValidationError.missingSparsebundle(imageURL.lastPathComponent)
            }
        }

        return (libraryURL, manifest)
    }

    static func createOpenedSession(
        from accessSession: LibraryAccessSession,
        manifest: DocumentLibraryManifest,
        password: String?
    ) throws -> LibraryAccessSession {
        switch manifest.storageMode {
        case .plainPackage:
            return LibraryAccessSession(
                packageURL: accessSession.packageURL,
                dataRootURL: accessSession.packageURL,
                startedAccessingSecurityScope: accessSession.startedAccessingSecurityScope,
                mountedVolume: nil
            )
        case .encryptedSparsebundle:
            let imageURL = sparsebundleURL(for: accessSession.packageURL, manifest: manifest)
            guard let password else {
                throw ValidationError.passwordRequired
            }
            let existingMountedVolume = try LibraryDiskImageService.findMountedVolume(for: imageURL)
            let mounted = try LibraryDiskImageService.attachSparsebundle(at: imageURL, password: password)
            let wrapped = MountedLibraryVolume(
                imageURL: mounted.imageURL,
                mountPointURL: mounted.mountPointURL,
                deviceEntry: mounted.deviceEntry,
                ownedByCurrentSession: existingMountedVolume == nil
            )
            do {
                try validateMountedDataRoot(at: wrapped.mountPointURL)
            } catch {
                if wrapped.ownedByCurrentSession {
                    try? LibraryDiskImageService.detach(mounted, force: true)
                }
                throw error
            }
            return LibraryAccessSession(
                packageURL: accessSession.packageURL,
                dataRootURL: wrapped.mountPointURL,
                startedAccessingSecurityScope: accessSession.startedAccessingSecurityScope,
                mountedVolume: wrapped
            )
        }
    }

    static func originalsDirectory(for libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent("Originals", isDirectory: true)
    }

    static func contains(_ candidateURL: URL, inLibrary libraryURL: URL) -> Bool {
        let libraryPath = libraryURL.standardizedFileURL.resolvingSymlinksInPath().path
        let candidatePath = candidateURL.standardizedFileURL.resolvingSymlinksInPath().path

        return candidatePath == libraryPath || candidatePath.hasPrefix(libraryPath + "/")
    }

    static func contains(
        _ candidateURL: URL,
        inLibraryPackage packageURL: URL?,
        dataRootURL: URL?
    ) -> Bool {
        if let packageURL, contains(candidateURL, inLibrary: packageURL) {
            return true
        }

        if let dataRootURL, contains(candidateURL, inLibrary: dataRootURL) {
            return true
        }

        return false
    }

    static func metadataDirectory(for libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent("Metadata", isDirectory: true)
    }

    static func metadataStoreURL(for libraryURL: URL) -> URL {
        metadataDirectory(for: libraryURL)
            .appendingPathComponent("library")
            .appendingPathExtension("sqlite")
    }

    static func openModelContainer(for libraryURL: URL) throws -> ModelContainer {
        let configuration = ModelConfiguration(
            "DocNestLibrary",
            url: metadataStoreURL(for: libraryURL),
            cloudKitDatabase: .none
        )

        let schema = Schema(versionedSchema: DocNestSchemaV4.self)

        return try ModelContainer(
            for: schema,
            migrationPlan: DocNestMigrationPlan.self,
            configurations: configuration
        )
    }

    static func refreshIntegrityArtifacts(
        packageURL: URL,
        dataRootURL: URL,
        manifest: DocumentLibraryManifest,
        migration: LibraryMigrationResult,
        packageRepair: LibraryRepairResult
    ) async throws -> LibraryIntegrityReport {
        try await Task.detached(priority: .utility) {
            let modelContainer = try openModelContainer(for: dataRootURL)
            let modelContext = ModelContext(modelContainer)
            let metadataRepair = try repairLibraryConsistency(
                for: dataRootURL,
                modelContext: modelContext
            )
            let repair = LibraryRepairResult(
                performedRepair: packageRepair.performedRepair || metadataRepair.performedRepair,
                actions: packageRepair.actions + metadataRepair.actions
            )
            return try writeIntegrityReport(
                packageURL: packageURL,
                dataRootURL: dataRootURL,
                manifest: manifest,
                migration: migration,
                repair: repair,
                modelContext: modelContext
            )
        }.value
    }

    static func writeIntegrityReport(
        packageURL: URL,
        dataRootURL: URL,
        manifest: DocumentLibraryManifest,
        migration: LibraryMigrationResult,
        repair: LibraryRepairResult,
        modelContext: ModelContext
    ) throws -> LibraryIntegrityReport {
        let issues = try collectIntegrityIssues(
            packageURL: packageURL,
            dataRootURL: dataRootURL,
            manifest: manifest,
            modelContext: modelContext
        )
        let documentCount = try modelContext.fetchCount(FetchDescriptor<DocumentRecord>())
        let report = LibraryIntegrityReport(
            generatedAt: .now,
            libraryPath: packageURL.path,
            manifestFormatVersion: manifest.formatVersion,
            schemaVersion: "4.0.0",
            migration: migration,
            repair: repair,
            documentCount: documentCount,
            issues: issues
        )
        let reportData = try JSONEncoder.prettyPrinted.encode(report)
        try reportData.write(to: diagnosticsReportURL(for: packageURL), options: .atomic)
        return report
    }

    static func repairLibraryConsistency(
        for libraryURL: URL,
        modelContext: ModelContext
    ) throws -> LibraryRepairResult {
        let documents = try modelContext.fetch(FetchDescriptor<DocumentRecord>())
        var actions: [LibraryRepairAction] = []

        for document in documents {
            guard let storedFilePath = document.storedFilePath else { continue }

            let fileURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)
            guard FileManager.default.fileExists(atPath: fileURL.path) else { continue }
            guard contains(fileURL, inLibrary: libraryURL) else { continue }

            if document.contentHash.isEmpty {
                document.contentHash = try hashFile(at: fileURL)
                actions.append(
                    LibraryRepairAction(
                        kind: .backfilledContentHash,
                        target: document.title,
                        message: "Backfilled missing content hash for \"\(document.title)\"."
                    )
                )
            }

            if document.fileSize <= 0 {
                let resourceValues = try fileURL.resourceValues(forKeys: [.fileSizeKey])
                document.fileSize = Int64(resourceValues.fileSize ?? 0)
                actions.append(
                    LibraryRepairAction(
                        kind: .backfilledFileSize,
                        target: document.title,
                        message: "Backfilled file size for \"\(document.title)\"."
                    )
                )
            }

            if document.pageCount <= 0,
               let pdfDocument = PDFDocument(url: fileURL) {
                document.pageCount = pdfDocument.pageCount
                actions.append(
                    LibraryRepairAction(
                        kind: .backfilledPageCount,
                        target: document.title,
                        message: "Backfilled page count for \"\(document.title)\"."
                    )
                )
            }
        }

        if !actions.isEmpty {
            try modelContext.save()
        }

        return LibraryRepairResult(performedRepair: !actions.isEmpty, actions: actions)
    }

    // MARK: - Library Lock

    static func readLockFile(for libraryURL: URL) -> LibraryLockFile? {
        let url = lockFileURL(for: libraryURL)
        guard let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder.libraryManifest.decode(LibraryLockFile.self, from: data)
    }

    static func acquireLock(for libraryURL: URL) throws {
        if let existing = readLockFile(for: libraryURL), !existing.isStale {
            let currentPID = ProcessInfo.processInfo.processIdentifier
            let currentHost = ProcessInfo.processInfo.hostName
            let isSameProcess = existing.pid == currentPID && existing.hostname == currentHost

            if !isSameProcess {
                let isSameHost = existing.hostname == currentHost
                let ownerStillRunning = isSameHost && kill(existing.pid, 0) == 0

                if ownerStillRunning {
                    throw LockError.lockedByAnotherInstance(existing)
                }
                // Owner process no longer exists — treat lock as stale.
            }
        }

        try writeLockFile(for: libraryURL)
    }

    static func refreshLock(for libraryURL: URL) throws {
        try writeLockFile(for: libraryURL)
    }

    static func releaseLock(for libraryURL: URL) {
        let url = lockFileURL(for: libraryURL)
        try? FileManager.default.removeItem(at: url)
    }

    private static func writeLockFile(for libraryURL: URL) throws {
        let lock = LibraryLockFile(
            hostname: ProcessInfo.processInfo.hostName,
            pid: ProcessInfo.processInfo.processIdentifier,
            updatedAt: .now
        )
        let data = try JSONEncoder.prettyPrinted.encode(lock)
        try data.write(to: lockFileURL(for: libraryURL), options: .atomic)
    }

    private static func lockFileURL(for libraryURL: URL) -> URL {
        diagnosticsDirectory(for: libraryURL)
            .appendingPathComponent(lockFileName)
    }

    private static func diagnosticsDirectory(for libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent("Diagnostics", isDirectory: true)
    }

    private static func diagnosticsReportURL(for libraryURL: URL) -> URL {
        diagnosticsDirectory(for: libraryURL)
            .appendingPathComponent(integrityReportFileName)
    }

    private static func collectIntegrityIssues(
        packageURL: URL,
        dataRootURL: URL,
        manifest: DocumentLibraryManifest,
        modelContext: ModelContext
    ) throws -> [LibraryIntegrityIssue] {
        var issues: [LibraryIntegrityIssue] = []

        if manifest.formatVersion != currentFormatVersion {
            issues.append(
                LibraryIntegrityIssue(
                    severity: .warning,
                    code: "manifest.version.outdated",
                    message: "Library manifest version is \(manifest.formatVersion), expected \(currentFormatVersion)."
                )
            )
        }

        let metadataStore = metadataStoreURL(for: dataRootURL)
        if !FileManager.default.fileExists(atPath: metadataStore.path) {
            issues.append(
                LibraryIntegrityIssue(
                    severity: .warning,
                    code: "metadata.store.missing",
                    message: "Metadata store is missing at \(metadataStore.lastPathComponent). A new store may be created on first save."
                )
            )
        }

        let documents = try modelContext.fetch(FetchDescriptor<DocumentRecord>())
        var seenHashes: [String: Int] = [:]

        for document in documents {
            if let storedFilePath = document.storedFilePath {
                let fileURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: dataRootURL)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    issues.append(
                        LibraryIntegrityIssue(
                            severity: .error,
                            code: "document.file.missing",
                            message: "Document \"\(document.title)\" references a missing stored file at \(storedFilePath)."
                        )
                    )
                }

                if !fileURL.standardizedFileURL.path.hasPrefix(dataRootURL.standardizedFileURL.path + "/") {
                    issues.append(
                        LibraryIntegrityIssue(
                            severity: .error,
                            code: "document.file.outside-library",
                            message: "Document \"\(document.title)\" resolves outside the library package."
                        )
                    )
                }
            } else if document.trashedAt == nil {
                issues.append(
                    LibraryIntegrityIssue(
                        severity: .warning,
                        code: "document.file.unset",
                        message: "Active document \"\(document.title)\" has no stored file path."
                    )
                )
            }

            if document.contentHash.isEmpty {
                issues.append(
                    LibraryIntegrityIssue(
                        severity: .warning,
                        code: "document.hash.empty",
                        message: "Document \"\(document.title)\" has an empty content hash."
                    )
                )
            } else {
                seenHashes[document.contentHash, default: 0] += 1
            }
        }

        for (hash, count) in seenHashes where count > 1 {
            issues.append(
                LibraryIntegrityIssue(
                    severity: .warning,
                    code: "document.hash.duplicate",
                    message: "Content hash \(String(hash.prefix(12))) is shared by \(count) documents."
                )
            )
        }

        return issues
    }

    private static func createRequiredDirectories(in libraryURL: URL) throws {
        try createDirectories(plainDataDirectories, in: libraryURL)
    }

    private static func writeManifest(_ manifest: DocumentLibraryManifest, for libraryURL: URL) throws {
        let manifestData = try JSONEncoder.prettyPrinted.encode(manifest)
        try manifestData.write(to: primaryManifestURL(for: libraryURL), options: .atomic)
    }

    private static func createDirectories(_ directories: [String], in rootURL: URL) throws {
        for directory in directories {
            try FileManager.default.createDirectory(
                at: rootURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private static func readManifest(for libraryURL: URL) throws -> DocumentLibraryManifest {
        let candidates = [primaryManifestURL(for: libraryURL), legacyManifestURL(for: libraryURL)]
        for url in candidates where FileManager.default.fileExists(atPath: url.path) {
            let manifestData = try Data(contentsOf: url)
            return try JSONDecoder.libraryManifest.decode(DocumentLibraryManifest.self, from: manifestData)
        }

        throw CocoaError(.fileNoSuchFile)
    }

    private static func legacyOrDefaultManifest(for libraryURL: URL) throws -> DocumentLibraryManifest {
        if let manifest = try? readManifest(for: libraryURL) {
            return manifest
        }

        return DocumentLibraryManifest(formatVersion: currentFormatVersion, createdAt: .now)
    }

    private static func validateMountedDataRoot(at rootURL: URL) throws {
        var isDirectory: ObjCBool = false
        for directory in encryptedInnerDirectories {
            let directoryURL = rootURL.appendingPathComponent(directory, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory),
                  isDirectory.boolValue else {
                throw ValidationError.missingMountedDirectory(directory)
            }
        }
    }

    private static func copyPlainLibraryContents(from packageURL: URL, to mountedRootURL: URL) throws {
        let fileManager = FileManager.default
        for directory in ["Metadata", "Originals", "Previews"] {
            let source = packageURL.appendingPathComponent(directory, isDirectory: true)
            let destination = mountedRootURL.appendingPathComponent(directory, isDirectory: true)

            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }

            if fileManager.fileExists(atPath: source.path) {
                try fileManager.copyItem(at: source, to: destination)
            } else {
                try fileManager.createDirectory(at: destination, withIntermediateDirectories: true)
            }
        }
    }

    private static func stagePlaintextPayloadsForRemoval(from packageURL: URL) throws -> URL {
        let fileManager = FileManager.default
        let backupRoot = packageURL.deletingLastPathComponent()
            .appendingPathComponent(".DocNestConversionBackup-\(UUID().uuidString)", isDirectory: true)
        try fileManager.createDirectory(at: backupRoot, withIntermediateDirectories: true)
        var movedDirectories: [String] = []

        do {
            for directory in ["Metadata", "Originals", "Previews"] {
                let source = packageURL.appendingPathComponent(directory, isDirectory: true)
                let backup = backupRoot.appendingPathComponent(directory, isDirectory: true)
                if fileManager.fileExists(atPath: source.path) {
                    try fileManager.moveItem(at: source, to: backup)
                    movedDirectories.append(directory)
                }
            }
            return backupRoot
        } catch {
            for directory in movedDirectories.reversed() {
                let backup = backupRoot.appendingPathComponent(directory, isDirectory: true)
                let source = packageURL.appendingPathComponent(directory, isDirectory: true)
                if fileManager.fileExists(atPath: source.path) {
                    try? fileManager.removeItem(at: source)
                }
                if fileManager.fileExists(atPath: backup.path) {
                    try fileManager.moveItem(at: backup, to: source)
                }
            }
            if fileManager.fileExists(atPath: backupRoot.path) {
                try? fileManager.removeItem(at: backupRoot)
            }
            throw error
        }
    }

    private static func restoreStagedPlaintextPayloads(_ backupRoot: URL, to packageURL: URL) throws {
        let fileManager = FileManager.default
        var restoredDirectories: [String] = []
        for directory in ["Metadata", "Originals", "Previews"] {
            let source = backupRoot.appendingPathComponent(directory, isDirectory: true)
            let destination = packageURL.appendingPathComponent(directory, isDirectory: true)
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            if fileManager.fileExists(atPath: source.path) {
                do {
                    try fileManager.moveItem(at: source, to: destination)
                    restoredDirectories.append(directory)
                } catch {
                    for restoredDirectory in restoredDirectories.reversed() {
                        let restoredSource = packageURL.appendingPathComponent(restoredDirectory, isDirectory: true)
                        let restoredBackup = backupRoot.appendingPathComponent(restoredDirectory, isDirectory: true)
                        if fileManager.fileExists(atPath: restoredBackup.path) {
                            try? fileManager.removeItem(at: restoredBackup)
                        }
                        if fileManager.fileExists(atPath: restoredSource.path) {
                            try? fileManager.moveItem(at: restoredSource, to: restoredBackup)
                        }
                    }
                    throw error
                }
            }
        }
        if fileManager.fileExists(atPath: backupRoot.path) {
            try fileManager.removeItem(at: backupRoot)
        }
    }

    private static func discardStagedPlaintextPayloads(_ backupRoot: URL) throws {
        if FileManager.default.fileExists(atPath: backupRoot.path) {
            try FileManager.default.removeItem(at: backupRoot)
        }
    }

    private static func combineWarnings(_ first: String?, _ second: String?) -> String? {
        let combined = [first, second]
            .compactMap { $0 }
            .joined(separator: "\n\n")
        return combined.isEmpty ? nil : combined
    }

    private static func hashFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer {
            try? handle.close()
        }

        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty {
            hasher.update(data: chunk)
        }

        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    enum LockError: LocalizedError {
        case lockedByAnotherInstance(LibraryLockFile)

        var errorDescription: String? {
            switch self {
            case .lockedByAnotherInstance(let lock):
                return "This library is currently open on \(lock.ownerDescription). Close it there first, or wait for the lock to expire."
            }
        }
    }

    static func selectedLibraryURL(from launchArguments: [String]) -> URL? {
        guard let argumentIndex = launchArguments.firstIndex(of: launchArgumentSelectedLibraryPath) else {
            return nil
        }

        let valueIndex = launchArguments.index(after: argumentIndex)
        guard valueIndex < launchArguments.endIndex else {
            return nil
        }

        let path = launchArguments[valueIndex]
        guard !path.hasPrefix("-") else {
            return nil
        }

        return URL(fileURLWithPath: path).standardizedFileURL
    }

    private static func normalizedLibraryURL(from url: URL) -> URL {
        guard url.pathExtension != packageExtension else {
            return url.standardizedFileURL
        }

        return url
            .deletingPathExtension()
            .appendingPathExtension(packageExtension)
            .standardizedFileURL
    }

    private static func isURLInTrash(_ url: URL) -> Bool {
        let standardizedPath = url.standardizedFileURL.resolvingSymlinksInPath().path
        let pathComponents = URL(fileURLWithPath: standardizedPath).pathComponents

        if pathComponents.contains(".Trash") || pathComponents.contains(".Trashes") {
            return true
        }

        if let userTrashURL = try? FileManager.default.url(
            for: .trashDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: false
        ) {
            let trashPath = userTrashURL.standardizedFileURL.resolvingSymlinksInPath().path
            if standardizedPath == trashPath || standardizedPath.hasPrefix(trashPath + "/") {
                return true
            }
        }

        return false
    }

    private static func primaryManifestURL(for libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent(manifestFileName)
    }

    private static func legacyManifestURL(for libraryURL: URL) -> URL {
        libraryURL
            .appendingPathComponent("Metadata", isDirectory: true)
            .appendingPathComponent(manifestFileName)
    }

    static func sparsebundleURL(for libraryURL: URL, manifest: DocumentLibraryManifest) -> URL {
        let relativePath = manifest.sparsebundleRelativePath ?? defaultSparsebundleRelativePath
        return libraryURL.appendingPathComponent(relativePath, isDirectory: false)
    }

    enum ValidationError: LocalizedError {
        case missingDirectory(String)
        case missingMountedDirectory(String)
        case missingSparsebundle(String)
        case passwordRequired

        var errorDescription: String? {
            switch self {
            case .missingDirectory(let directory):
                return "The selected library is missing the required \(directory) directory."
            case .missingMountedDirectory(let directory):
                return "The encrypted library image is missing the required \(directory) directory."
            case .missingSparsebundle(let name):
                return "The encrypted library image \(name) is missing."
            case .passwordRequired:
                return "The encrypted library needs a password before it can be opened."
            }
        }
    }
}

private extension JSONEncoder {
    static var prettyPrinted: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}

private extension JSONDecoder {
    static var libraryManifest: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
