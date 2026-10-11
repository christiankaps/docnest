import CryptoKit
import Foundation
import PDFKit

/// Owns all library writes. Each import publishes one complete directory using a same-volume rename.
actor LibraryStore {
    enum ImportPhase: Sendable { case copied, validated, metadataWritten, organizationWillWrite, cleanupWillRemove }
    typealias Checkpoint = @Sendable (ImportPhase) throws -> Void

    let root: URL
    nonisolated let accessPolicy: LibraryAccessPolicy
    private let exportRoot: URL
    private let checkpoint: Checkpoint
    private let now: @Sendable () -> Date
    private var organization: LibraryOrganization?
    private var records: [LibraryDocument]?
    private let files = FileManager.default

    static var defaultRoot: URL {
        URL.applicationSupportDirectory.appending(path: "DocNestLibrary", directoryHint: .isDirectory)
    }

    init(root: URL = LibraryStore.defaultRoot, exportRoot: URL = URL.temporaryDirectory.appending(path: "DocNestExports"),
         checkpoint: @escaping Checkpoint = { _ in }, now: @escaping @Sendable () -> Date = { Date() }, accessPolicy: LibraryAccessPolicy? = nil) {
        self.root = root
        let isLiveRoot = root.resolvingSymlinksInPath().standardizedFileURL.path == Self.defaultRoot.resolvingSymlinksInPath().standardizedFileURL.path
        self.accessPolicy = accessPolicy ?? LibraryAccessPolicy(locked: isLiveRoot && UserDefaults.standard.bool(forKey: "libraryLockEnabled"))
        self.exportRoot = exportRoot
        self.checkpoint = checkpoint
        self.now = now
    }

    private var documentsDirectory: URL { root.appending(path: "Documents") }
    private var stagingDirectory: URL { root.appending(path: "Staging") }

    func load() throws -> [LibraryDocument] {
        try accessPolicy.requireUnlocked()
        records = nil
        organization = nil
        try createDirectory(documentsDirectory)
        try createDirectory(stagingDirectory)
        let organizationURL = root.appending(path: "organization.json")
        var saved: LibraryOrganization
        if files.fileExists(atPath: organizationURL.path) {
            do {
                let data = try Data(contentsOf: organizationURL)
                struct Header: Decodable { let schemaVersion: Int }
                guard [1, 2].contains(try JSONDecoder().decode(Header.self, from: data).schemaVersion) else { throw LibraryError.unsupportedVersion }
                saved = try JSONDecoder().decode(LibraryOrganization.self, from: data)
                saved.schemaVersion = 2
            } catch let error as LibraryError { throw error }
            catch { throw LibraryError.invalidLibrary }
        } else {
            saved = LibraryOrganization()
        }
        var loaded: [LibraryDocument] = []
        for folder in try files.contentsOfDirectory(at: documentsDirectory, includingPropertiesForKeys: nil) {
            guard UUID(uuidString: folder.lastPathComponent) != nil else { throw LibraryError.invalidLibrary }
            if saved.purgedIDs?.contains(UUID(uuidString: folder.lastPathComponent)!) == true { continue }
            let record: LibraryDocument
            do {
                let data = try Data(contentsOf: folder.appending(path: "metadata.json"))
                struct Header: Decodable { let schemaVersion: Int }
                guard try JSONDecoder().decode(Header.self, from: data).schemaVersion == 1 else { throw LibraryError.unsupportedVersion }
                record = try JSONDecoder().decode(LibraryDocument.self, from: data)
            } catch let error as LibraryError { throw error }
            catch { throw LibraryError.invalidLibrary }
            guard record.id.uuidString == folder.lastPathComponent,
                  record.documentDate.isValid, record.pageCount > 0, record.byteCount > 0,
                  record.contentHash.count == 64,
                  record.filename == Self.safeFilename(record.filename),
                  files.fileExists(atPath: folder.appending(path: "original.pdf").path),
                  !loaded.contains(where: { $0.id == record.id }) else {
                throw LibraryError.invalidLibrary
            }
            let attributes = try files.attributesOfItem(atPath: folder.appending(path: "original.pdf").path)
            let size = attributes[.size] as? NSNumber
            guard size?.int64Value == record.byteCount, attributes[.type] as? FileAttributeType == .typeRegular else {
                throw LibraryError.invalidLibrary
            }
            loaded.append(record)
        }
        // Only incomplete, unpublished transactions are removed. Never repair/reset accepted originals silently.
        for abandoned in try files.contentsOfDirectory(at: stagingDirectory, includingPropertiesForKeys: nil) {
            try files.removeItem(at: abandoned)
        }
        if files.fileExists(atPath: exportRoot.path) { try files.removeItem(at: exportRoot) }
        try validate(saved, documents: loaded)
        if !files.fileExists(atPath: organizationURL.path) { try writeOrganization(saved) }
        organization = saved
        records = Self.sorted(loaded.map { saved.applying(to: $0) })
        try cleanupExpired()
        return try allDocuments()
    }

    func importPDF(from source: URL, importedAt: Date = Date()) throws -> ImportResult {
        try accessPolicy.requireUnlocked()
        guard var current = records else { throw LibraryError.notLoaded }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let id = UUID()
        let staging = stagingDirectory.appending(path: id.uuidString)
        try createDirectory(staging)
        defer { try? files.removeItem(at: staging) }
        let pdfURL = staging.appending(path: "original.pdf")
        var coordinationError: NSError?
        var copyError: Error?
        NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinationError) { coordinatedURL in
            do { try files.copyItem(at: coordinatedURL, to: pdfURL) }
            catch { copyError = error }
        }
        if let error = coordinationError ?? copyError { throw error }
        try checkpoint(.copied)
        let pageCount = try Self.validatePDF(at: pdfURL)
        try files.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: pdfURL.path)
        let hash = try Self.hash(at: pdfURL)
        if var existing = current.first(where: { $0.contentHash == hash }) {
            if existing.deletedAt != nil {
                try recover(existing.id)
                existing = records!.first { $0.id == existing.id }!
            }
            return ImportResult(document: existing, isDuplicate: true)
        }
        try checkpoint(.validated)
        let size = try files.attributesOfItem(atPath: pdfURL.path)[.size] as! NSNumber
        let document = LibraryDocument(
            schemaVersion: 1, id: id,
            filename: Self.availableFilename(source.lastPathComponent, occupied: Set(current.map { Self.nameKey($0.filename) })),
            contentHash: hash, byteCount: size.int64Value, pageCount: pageCount,
            documentDate: DocumentDate(importedAt, calendar: Self.localGregorian), dateSource: .importFallback,
            importedAt: importedAt, reviewState: .inbox, processingState: .notStarted
        )
        let data = try JSONEncoder().encode(document)
        try data.write(to: staging.appending(path: "metadata.json"), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        try checkpoint(.metadataWritten)
        try files.moveItem(at: staging, to: documentsDirectory.appending(path: id.uuidString))
        current.append(document)
        records = Self.sorted(current)
        return ImportResult(document: document, isDuplicate: false)
    }

    func allDocuments() throws -> [LibraryDocument] {
        try accessPolicy.requireUnlocked()
        guard let records else { throw LibraryError.notLoaded }
        return records.filter { $0.deletedAt == nil }
    }

    func allLabels() throws -> [LibraryLabel] {
        try accessPolicy.requireUnlocked()
        guard let organization, records != nil else { throw LibraryError.notLoaded }
        return organization.labels.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    @discardableResult
    func createLabel(name: String) throws -> LibraryLabel {
        try accessPolicy.requireUnlocked()
        guard var next = organization, records != nil else { throw LibraryError.notLoaded }
        let label = LibraryLabel(id: UUID(), starter: nil, customName: try labelName(name, excluding: nil))
        next.labels.append(label)
        try commit(next)
        return label
    }

    func renameLabel(_ id: UUID, name: String) throws {
        try accessPolicy.requireUnlocked()
        guard var next = organization, records != nil else { throw LibraryError.notLoaded }
        guard let index = next.labels.firstIndex(where: { $0.id == id }) else { throw LibraryError.invalidLabel }
        next.labels[index].customName = try labelName(name, excluding: id)
        try commit(next)
    }

    func deleteLabel(_ id: UUID) throws {
        try accessPolicy.requireUnlocked()
        guard var next = organization, records != nil else { throw LibraryError.notLoaded }
        next.labels.removeAll { $0.id == id }
        for key in Array(next.documents.keys) { next.documents[key]?.labelIDs.remove(id) }
        try commit(next)
    }

    func updateDocument(_ id: UUID, labels: Set<UUID>? = nil, manualDate: DocumentDate? = nil, reviewed: Bool = false) throws {
        try accessPolicy.requireUnlocked()
        guard var next = organization, let records else { throw LibraryError.notLoaded }
        guard let record = records.first(where: { $0.id == id && $0.deletedAt == nil }) else { throw LibraryError.missingDocument }
        var edit = next.documents[id.uuidString] ?? DocumentOrganization(reviewState: record.reviewState)
        if let labels {
            guard labels.isSubset(of: Set(next.labels.map(\.id))) else { throw LibraryError.invalidLabel }
            edit.labelIDs = labels
        }
        if let manualDate {
            guard manualDate.isValid else { throw LibraryError.invalidDate }
            edit.manualDate = manualDate
        }
        if reviewed { edit.reviewState = .reviewed }
        next.documents[id.uuidString] = edit
        try commit(next)
    }

    func recentlyDeleted() throws -> [LibraryDocument] {
        try accessPolicy.requireUnlocked()
        guard let records else { throw LibraryError.notLoaded }
        return records.filter { $0.deletedAt != nil }.sorted { $0.deletedAt! > $1.deletedAt! }
    }

    func renameDocument(_ id: UUID, name: String) throws {
        try accessPolicy.requireUnlocked()
        guard var next = organization, let records else { throw LibraryError.notLoaded }
        guard let record = records.first(where: { $0.id == id && $0.deletedAt == nil }) else { throw LibraryError.missingDocument }
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryError.invalidFilename }
        var edit = next.documents[id.uuidString] ?? DocumentOrganization(reviewState: record.reviewState)
        edit.filename = Self.availableFilename(name, occupied: Set(records.filter { $0.id != id }.map { Self.nameKey($0.filename) }))
        next.documents[id.uuidString] = edit
        try commit(next)
    }

    func addLabels(_ labels: Set<UUID>, to ids: Set<UUID>) throws {
        try accessPolicy.requireUnlocked()
        guard var next = organization, let records else { throw LibraryError.notLoaded }
        guard labels.isSubset(of: Set(next.labels.map(\.id))), ids.isSubset(of: Set(records.filter { $0.deletedAt == nil }.map(\.id))) else { throw LibraryError.invalidLabel }
        for record in records where ids.contains(record.id) {
            var edit = next.documents[record.id.uuidString] ?? DocumentOrganization(reviewState: record.reviewState)
            edit.labelIDs.formUnion(labels)
            next.documents[record.id.uuidString] = edit
        }
        try commit(next)
    }

    func deleteDocument(_ id: UUID) throws {
        try accessPolicy.requireUnlocked()
        guard var next = organization, let record = records?.first(where: { $0.id == id && $0.deletedAt == nil }) else { throw LibraryError.missingDocument }
        var edit = next.documents[id.uuidString] ?? DocumentOrganization(reviewState: record.reviewState)
        edit.deletedAt = now()
        next.documents[id.uuidString] = edit
        try commit(next)
    }

    func recover(_ id: UUID) throws {
        try accessPolicy.requireUnlocked()
        guard var next = organization, let record = records?.first(where: { $0.id == id && $0.deletedAt != nil }),
              now().timeIntervalSince(record.deletedAt!) < 30 * 86400 else { throw LibraryError.missingDocument }
        next.documents[id.uuidString]?.deletedAt = nil
        try commit(next)
    }

    /// Commit durable tombstones first; interrupted or failed removals are retried on the next execution.
    func cleanupExpired() throws {
        try accessPolicy.requireUnlocked()
        guard var next = organization, let records else { throw LibraryError.notLoaded }
        let expired = records.filter { $0.deletedAt.map { now().timeIntervalSince($0) >= 30 * 86400 } ?? false }
        if !expired.isEmpty {
            next.purgedIDs = (next.purgedIDs ?? []).union(expired.map(\.id))
            for record in expired { next.documents.removeValue(forKey: record.id.uuidString) }
            let remaining = records.filter { !(next.purgedIDs ?? []).contains($0.id) }
            try validate(next, documents: remaining)
            try writeOrganization(next)
            organization = next
            self.records = remaining
        }
        for id in next.purgedIDs ?? [] {
            let folder = documentsDirectory.appending(path: id.uuidString)
            if files.fileExists(atPath: folder.path) {
                try checkpoint(.cleanupWillRemove)
                try files.removeItem(at: folder)
            }
        }
    }

    func exportCopies(for ids: Set<UUID>) throws -> [URL] {
        try accessPolicy.requireUnlocked()
        var copies: [URL] = []
        do {
            for id in ids.sorted(by: { $0.uuidString < $1.uuidString }) { copies.append(try exportCopy(for: id)) }
            return copies
        } catch {
            for url in copies { removeExport(url) }
            throw error
        }
    }

    private func labelName(_ name: String, excluding id: UUID?) throws -> String {
        let clean = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !clean.isEmpty, clean.rangeOfCharacter(from: .controlCharacters) == nil,
              organization?.labels.contains(where: { $0.id != id && Self.nameKey($0.name) == Self.nameKey(clean) }) == false else {
            throw LibraryError.invalidLabel
        }
        return clean
    }

    private func validate(_ snapshot: LibraryOrganization, documents: [LibraryDocument]) throws {
        let ids = Set(snapshot.labels.map(\.id))
        guard ids.count == snapshot.labels.count,
              snapshot.labels.allSatisfy({ label in
                  (label.starter == nil ? label.customName != nil : label.id == label.starter?.id)
                  && !label.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                  && label.name.rangeOfCharacter(from: .controlCharacters) == nil
              }) else { throw LibraryError.invalidLibrary }
        guard (snapshot.purgedIDs ?? []).isDisjoint(with: Set(documents.map(\.id))) else { throw LibraryError.invalidLibrary }
        let effective = documents.map { snapshot.applying(to: $0) }
        guard Set(effective.map { Self.nameKey($0.filename) }).count == effective.count else { throw LibraryError.invalidLibrary }
        let documentIDs = Set(documents.map { $0.id.uuidString })
        for (id, edit) in snapshot.documents {
            guard documentIDs.contains(id), edit.labelIDs.isSubset(of: ids), edit.manualDate?.isValid != false, edit.deletedAt?.timeIntervalSinceReferenceDate.isFinite != false,
                  edit.filename.map({ $0 == Self.safeFilename($0) }) != false else {
                throw LibraryError.invalidLibrary
            }
        }
    }

    private func writeOrganization(_ next: LibraryOrganization) throws {
        try checkpoint(.organizationWillWrite)
        try JSONEncoder().encode(next).write(to: root.appending(path: "organization.json"),
            options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    private func commit(_ next: LibraryOrganization) throws {
        guard let records else { throw LibraryError.notLoaded }
        try validate(next, documents: records)
        try writeOrganization(next)
        organization = next
        self.records = Self.sorted(records.map { next.applying(to: $0) })
    }

    func originalURL(for id: UUID) throws -> URL {
        try accessPolicy.requireUnlocked()
        guard records?.contains(where: { $0.id == id && $0.deletedAt == nil }) == true else { throw LibraryError.missingDocument }
        return documentsDirectory.appending(path: id.uuidString).appending(path: "original.pdf")
    }

    /// Always creates a distinct copy, never a hard link or a URL into the live library.
    func exportCopy(for id: UUID) throws -> URL {
        try accessPolicy.requireUnlocked()
        guard let record = records?.first(where: { $0.id == id && $0.deletedAt == nil }) else { throw LibraryError.missingDocument }
        let folder = exportRoot.appending(path: UUID().uuidString)
        try createDirectory(folder)
        let destination = folder.appending(path: record.filename)
        do { try files.copyItem(at: originalURL(for: id), to: destination) }
        catch { try? files.removeItem(at: folder); throw error }
        return destination
    }

    func removeExport(_ url: URL) {
        guard url.deletingLastPathComponent().deletingLastPathComponent().standardizedFileURL.path == exportRoot.standardizedFileURL.path else { return }
        try? files.removeItem(at: url.deletingLastPathComponent())
    }

    func search(document id: UUID, text: String) throws -> [PDFSearchHit] {
        try accessPolicy.requireUnlocked()
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return [] }
        guard let pdf = PDFDocument(url: try originalURL(for: id)) else { throw LibraryError.invalidPDF }
        return pdf.findString(text, withOptions: [.caseInsensitive]).compactMap { match in
            guard let page = match.pages.first else { return nil }
            let range = match.range(at: 0, on: page)
            match.extendForLineBoundaries()
            return PDFSearchHit(pageIndex: pdf.index(for: page), range: range, snippet: match.string ?? text)
        }
    }

    private func createDirectory(_ url: URL) throws {
        try files.createDirectory(at: url, withIntermediateDirectories: true,
                                  attributes: [.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
    }

    private static var localGregorian: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = .current
        return calendar
    }

    static func validatePDF(at url: URL) throws -> Int {
        guard try FileManager.default.attributesOfItem(atPath: url.path)[.type] as? FileAttributeType == .typeRegular else {
            throw LibraryError.invalidPDF
        }
        guard let pdf = PDFDocument(url: url) else { throw LibraryError.invalidPDF }
        guard !pdf.isEncrypted else { throw LibraryError.encryptedPDF }
        guard pdf.pageCount > 0 else { throw LibraryError.invalidPDF }
        for index in 0..<pdf.pageCount {
            guard let page = pdf.page(at: index), page.pageRef != nil else { throw LibraryError.invalidPDF }
            let bounds = page.bounds(for: .mediaBox)
            guard bounds.width.isFinite, bounds.height.isFinite, bounds.width > 0, bounds.height > 0 else { throw LibraryError.invalidPDF }
        }
        return pdf.pageCount
    }

    private static func hash(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let chunk = try handle.read(upToCount: 1_048_576), !chunk.isEmpty { hash.update(data: chunk) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func safeFilename(_ name: String) -> String {
        var clean = name.components(separatedBy: CharacterSet.controlCharacters.union(CharacterSet(charactersIn: "/"))).joined(separator: "_")
        if clean.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { clean = "Document.pdf" }
        if !(clean as NSString).pathExtension.lowercased().elementsEqual("pdf") { clean += ".pdf" }
        return clean
    }

    static func nameKey(_ name: String) -> String { name.precomposedStringWithCanonicalMapping.lowercased() }

    private static func availableFilename(_ name: String, occupied: Set<String>) -> String {
        let filename = safeFilename(name)
        guard occupied.contains(nameKey(filename)) else { return filename }
        let stem = (filename as NSString).deletingPathExtension
        let ext = (filename as NSString).pathExtension
        var number = 2
        while occupied.contains(nameKey("\(stem)_\(number).\(ext)")) { number += 1 }
        return "\(stem)_\(number).\(ext)"
    }

    private static func sorted(_ documents: [LibraryDocument]) -> [LibraryDocument] {
        documents.sorted {
            let a = $0.documentDate, b = $1.documentDate
            if a != b { return (a.year, a.month, a.day) > (b.year, b.month, b.day) }
            let order = $0.filename.localizedStandardCompare($1.filename)
            return order == .orderedSame ? $0.id.uuidString < $1.id.uuidString : order == .orderedAscending
        }
    }
}
