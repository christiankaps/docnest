import AppKit
import CryptoKit
import Foundation
import PDFKit
import SwiftData
import UniformTypeIdentifiers

/// Custom UTType used for DocNest library packages.
extension UTType {
    static let docNestLibrary = UTType("com.kaps.docnest.library")!
}

/// Manifest stored in `Metadata/library.json` for every library package.
struct DocumentLibraryManifest: Codable {
    let formatVersion: Int
    let createdAt: Date
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

/// Filesystem and package management service for `.docnestlibrary` bundles.
///
/// This service owns creation, validation, repair, persistence of the selected
/// library reference, lock-file handling, and integrity-report generation.
enum DocumentLibraryService {
    static let packageExtension = "docnestlibrary"
    static let currentFormatVersion = 1

    struct LibraryAccessSession {
        let url: URL
        let startedAccessingSecurityScope: Bool
    }

    private static let persistedLibraryPathKey = "selectedLibraryPath"
    private static let persistedLibraryBookmarkKey = "selectedLibraryBookmark"
    private static let launchArgumentSelectedLibraryPath = "-selectedLibraryPath"
    private static let manifestFileName = "library.json"
    private static let lockFileName = ".lock"
    private static let integrityReportFileName = "integrity-report.json"
    private static let requiredDirectories = [
        "Metadata",
        "Originals",
        "Previews",
        "Diagnostics"
    ]

    /// Restores the previously selected library, preferring an explicit launch
    /// argument over persisted bookmark or path state.
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

    /// Persists or clears the library reference used for startup restoration.
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
            url: standardizedURL,
            startedAccessingSecurityScope: startedAccessingSecurityScope
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

    /// Creates a new library package with the required directory structure and manifest.
    static func createLibrary(at url: URL) throws -> URL {
        let libraryURL = normalizedLibraryURL(from: url)
        try FileManager.default.createDirectory(at: libraryURL, withIntermediateDirectories: true)

        try createRequiredDirectories(in: libraryURL)
        try writeManifest(
            DocumentLibraryManifest(formatVersion: currentFormatVersion, createdAt: .now),
            for: libraryURL
        )

        return libraryURL
    }

    /// Ensures the required library-package structure exists and repairs missing
    /// package-level components when they can be recreated safely.
    static func repairLibraryPackageIfNeeded(at url: URL) throws -> LibraryRepairResult {
        let libraryURL = normalizedLibraryURL(from: url)
        var actions: [LibraryRepairAction] = []

        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: libraryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
            throw CocoaError(.fileNoSuchFile)
        }

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

        let manifestURL = manifestURL(for: libraryURL)
        if !FileManager.default.fileExists(atPath: manifestURL.path) {
            let manifest = DocumentLibraryManifest(formatVersion: currentFormatVersion, createdAt: .now)
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

        // Future migrations go here, applied in order:
        // if manifest.formatVersion < 2 { ... }

        let updatedManifest = DocumentLibraryManifest(
            formatVersion: currentFormatVersion,
            createdAt: manifest.createdAt
        )
        let data = try JSONEncoder.prettyPrinted.encode(updatedManifest)
        try data.write(to: manifestURL(for: libraryURL), options: .atomic)

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

        for directory in requiredDirectories {
            let directoryURL = libraryURL.appendingPathComponent(directory, isDirectory: true)
            guard FileManager.default.fileExists(atPath: directoryURL.path, isDirectory: &isDirectory), isDirectory.boolValue else {
                throw ValidationError.missingDirectory(directory)
            }
        }

        let manifestData = try Data(contentsOf: manifestURL(for: libraryURL))
        let manifest = try JSONDecoder.libraryManifest.decode(DocumentLibraryManifest.self, from: manifestData)

        return (libraryURL, manifest)
    }

    static func originalsDirectory(for libraryURL: URL) -> URL {
        libraryURL.appendingPathComponent("Originals", isDirectory: true)
    }

    static func contains(_ candidateURL: URL, inLibrary libraryURL: URL) -> Bool {
        let libraryPath = libraryURL.standardizedFileURL.resolvingSymlinksInPath().path
        let candidatePath = candidateURL.standardizedFileURL.resolvingSymlinksInPath().path

        return candidatePath == libraryPath || candidatePath.hasPrefix(libraryPath + "/")
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
        for libraryURL: URL,
        manifest: DocumentLibraryManifest,
        migration: LibraryMigrationResult,
        packageRepair: LibraryRepairResult
    ) async throws -> LibraryIntegrityReport {
        try await Task.detached(priority: .utility) {
            let modelContainer = try openModelContainer(for: libraryURL)
            let modelContext = ModelContext(modelContainer)
            let metadataRepair = try repairLibraryConsistency(
                for: libraryURL,
                modelContext: modelContext
            )
            let repair = LibraryRepairResult(
                performedRepair: packageRepair.performedRepair || metadataRepair.performedRepair,
                actions: packageRepair.actions + metadataRepair.actions
            )
            return try writeIntegrityReport(
                for: libraryURL,
                manifest: manifest,
                migration: migration,
                repair: repair,
                modelContext: modelContext
            )
        }.value
    }

    static func writeIntegrityReport(
        for libraryURL: URL,
        manifest: DocumentLibraryManifest,
        migration: LibraryMigrationResult,
        repair: LibraryRepairResult,
        modelContext: ModelContext
    ) throws -> LibraryIntegrityReport {
        let issues = try collectIntegrityIssues(
            for: libraryURL,
            manifest: manifest,
            modelContext: modelContext
        )
        let documentCount = try modelContext.fetchCount(FetchDescriptor<DocumentRecord>())
        let report = LibraryIntegrityReport(
            generatedAt: .now,
            libraryPath: libraryURL.path,
            manifestFormatVersion: manifest.formatVersion,
            schemaVersion: "4.0.0",
            migration: migration,
            repair: repair,
            documentCount: documentCount,
            issues: issues
        )
        let reportData = try JSONEncoder.prettyPrinted.encode(report)
        try reportData.write(to: diagnosticsReportURL(for: libraryURL), options: .atomic)
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
        metadataDirectory(for: libraryURL)
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
        for libraryURL: URL,
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

        let metadataStore = metadataStoreURL(for: libraryURL)
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
                let fileURL = DocumentStorageService.fileURL(for: storedFilePath, libraryURL: libraryURL)
                if !FileManager.default.fileExists(atPath: fileURL.path) {
                    issues.append(
                        LibraryIntegrityIssue(
                            severity: .error,
                            code: "document.file.missing",
                            message: "Document \"\(document.title)\" references a missing stored file at \(storedFilePath)."
                        )
                    )
                }

                if !fileURL.standardizedFileURL.path.hasPrefix(libraryURL.standardizedFileURL.path + "/") {
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
        for directory in requiredDirectories {
            try FileManager.default.createDirectory(
                at: libraryURL.appendingPathComponent(directory, isDirectory: true),
                withIntermediateDirectories: true
            )
        }
    }

    private static func writeManifest(_ manifest: DocumentLibraryManifest, for libraryURL: URL) throws {
        let manifestData = try JSONEncoder.prettyPrinted.encode(manifest)
        try manifestData.write(to: manifestURL(for: libraryURL), options: .atomic)
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

    private static func manifestURL(for libraryURL: URL) -> URL {
        libraryURL
            .appendingPathComponent("Metadata", isDirectory: true)
            .appendingPathComponent(manifestFileName)
    }

    enum ValidationError: LocalizedError {
        case missingDirectory(String)

        var errorDescription: String? {
            switch self {
            case .missingDirectory(let directory):
                return "The selected library is missing the required \(directory) directory."
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
