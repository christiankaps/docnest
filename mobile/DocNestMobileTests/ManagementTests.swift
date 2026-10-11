import XCTest
@testable import DocNestMobile

@MainActor
final class ManagementTests: XCTestCase {
    private var sandbox: URL!
    private var root: URL { sandbox.appending(path: "Library") }
    override func setUp() async throws {
        sandbox = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: sandbox) }
    private func store(time: Date = Date(), checkpoint: @escaping LibraryStore.Checkpoint = { _ in }) -> LibraryStore {
        LibraryStore(root: root, exportRoot: sandbox.appending(path: "Exports"), checkpoint: checkpoint, now: { time })
    }
    private func source(_ name: String, text: String) throws -> URL {
        let url = sandbox.appending(path: name)
        try DevelopmentFixtures.pdf(text: text, pages: 1).write(to: url)
        return url
    }

    func testRenameCollisionBulkLabelsCopiesAndRecoveryPreserveOriginals() async throws {
        let library = store()
        _ = try await library.load()
        let input = try source("First.pdf", text: "First")
        let a = try await library.importPDF(from: input).document
        let b = try await library.importPDF(from: source("Second.pdf", text: "Second")).document
        try await library.updateDocument(a.id, labels: [StarterLabel.home.id], manualDate: DocumentDate(Date()), reviewed: true)
        try await library.renameDocument(a.id, name: "Second.pdf")
        try await library.addLabels([StarterLabel.taxes.id], to: [a.id, b.id])
        let before = try await library.allDocuments()
        let edited = try XCTUnwrap(before.first { $0.id == a.id })
        XCTAssertEqual(edited.filename, "Second_2.pdf")
        XCTAssertEqual(edited.labelIDs, [StarterLabel.home.id, StarterLabel.taxes.id])
        let copies = try await library.exportCopies(for: [a.id, b.id])
        XCTAssertEqual(Set(copies.map(\.lastPathComponent)), ["Second.pdf", "Second_2.pdf"])
        XCTAssertEqual(try Data(contentsOf: copies.first { $0.lastPathComponent == edited.filename }!), try Data(contentsOf: input))
        for url in copies { await library.removeExport(url); XCTAssertFalse(FileManager.default.fileExists(atPath: url.path)) }
        try await library.deleteDocument(a.id)
        let active = try await library.allDocuments()
        XCTAssertEqual(active.map(\.id), [b.id])
        do { _ = try await library.originalURL(for: a.id); XCTFail("Deleted document exposed") } catch { XCTAssertEqual(error as? LibraryError, .missingDocument) }
        let reopened = store()
        _ = try await reopened.load()
        let deleted = try await reopened.recentlyDeleted()
        XCTAssertEqual(deleted.first?.labelIDs, edited.labelIDs)
        try await reopened.recover(a.id)
        let recovered = try await reopened.allDocuments()
        XCTAssertEqual(recovered, before)
        let original = try await reopened.originalURL(for: a.id)
        XCTAssertEqual(try Data(contentsOf: original), try Data(contentsOf: input))
        // Reuse a renamed-away filename: immutable import names may now collide, effective names may not.
        _ = try await reopened.importPDF(from: source("First.pdf", text: "Third"))
        let reloaded = try await store().load()
        XCTAssertEqual(reloaded.count, 3)
    }

    func testRetentionBoundaryFailedCleanupAndInterruptedRemovalResume() async throws {
        let start = Date(timeIntervalSinceReferenceDate: 800_000_000)
        let library = store(time: start)
        _ = try await library.load()
        let a = try await library.importPDF(from: source("Keep.pdf", text: "Keep")).document
        try await library.deleteDocument(a.id)
        let almost = store(time: start.addingTimeInterval(30 * 86400 - 1))
        _ = try await almost.load()
        let retained = try await almost.recentlyDeleted()
        XCTAssertEqual(retained.count, 1)
        let expired = store(time: start.addingTimeInterval(30 * 86400), checkpoint: {
            if $0 == .cleanupWillRemove { throw CocoaError(.fileWriteNoPermission) }
        })
        do { _ = try await expired.load(); XCTFail("Cleanup failure suppressed") } catch { }
        let folder = root.appending(path: "Documents/\(a.id.uuidString)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.path))
        // Simulate termination during directory removal after durable tombstone publication.
        try FileManager.default.removeItem(at: folder.appending(path: "original.pdf"))
        let resumed = store(time: start.addingTimeInterval(31 * 86400))
        let active = try await resumed.load()
        let deleted = try await resumed.recentlyDeleted()
        XCTAssertTrue(active.isEmpty)
        XCTAssertTrue(deleted.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: folder.path))
        do { try await resumed.recover(a.id); XCTFail("Expired recovery accepted") } catch { XCTAssertEqual(error as? LibraryError, .missingDocument) }
    }

    func testFailedOrganizationWritesPreserveRenameDeletionAndBulkAssignments() async throws {
        let library = store()
        _ = try await library.load()
        let a = try await library.importPDF(from: source("Original.pdf", text: "Original")).document
        let before = try Data(contentsOf: root.appending(path: "organization.json"))
        let failing = store(checkpoint: { if $0 == .organizationWillWrite { throw CocoaError(.fileWriteOutOfSpace) } })
        _ = try await failing.load()
        do { try await failing.renameDocument(a.id, name: "Changed"); XCTFail() } catch { }
        do { try await failing.deleteDocument(a.id); XCTFail() } catch { }
        do { try await failing.addLabels([StarterLabel.taxes.id], to: [a.id]); XCTFail() } catch { }
        let active = try await failing.allDocuments()
        XCTAssertEqual(active, [a])
        XCTAssertEqual(try Data(contentsOf: root.appending(path: "organization.json")), before)
        let copies = try await failing.exportCopies(for: [a.id])
        await failing.removeExport(copies[0])
        do { _ = try await failing.exportCopies(for: [a.id, UUID()]); XCTFail() } catch { }
        let remaining = try FileManager.default.contentsOfDirectory(at: sandbox.appending(path: "Exports"), includingPropertiesForKeys: nil)
        XCTAssertTrue(remaining.isEmpty)
    }

    func testVersionOneOrganizationUpgradeAndFailedRecoveryKeepEdits() async throws {
        let library = store()
        _ = try await library.load()
        let a = try await library.importPDF(from: source("Legacy.pdf", text: "Legacy")).document
        try await library.updateDocument(a.id, labels: [StarterLabel.home.id], reviewed: true)
        let snapshot = root.appending(path: "organization.json")
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: snapshot)) as? [String: Any])
        json["schemaVersion"] = 1
        json.removeValue(forKey: "purgedIDs")
        try JSONSerialization.data(withJSONObject: json).write(to: snapshot)
        let upgraded = store()
        let old = try await upgraded.load()
        XCTAssertEqual(old.first?.labelIDs, [StarterLabel.home.id])
        XCTAssertEqual(old.first?.reviewState, .reviewed)
        try await upgraded.deleteDocument(a.id)
        let before = try Data(contentsOf: snapshot)
        let failing = store(checkpoint: { if $0 == .organizationWillWrite { throw CocoaError(.fileWriteOutOfSpace) } })
        _ = try await failing.load()
        do { try await failing.recover(a.id); XCTFail("Failed recovery reported success") } catch { }
        let deleted = try await failing.recentlyDeleted()
        XCTAssertEqual(deleted.count, 1)
        XCTAssertEqual(try Data(contentsOf: snapshot), before)
        let b = try await upgraded.importPDF(from: source("Legacy.pdf", text: "Different")).document
        XCTAssertEqual(b.filename, "Legacy_2.pdf", "Retained deleted names stay reserved")
        try await upgraded.recover(a.id)
        let recovered = try await upgraded.allDocuments()
        XCTAssertEqual(recovered.first { $0.id == a.id }?.filename, "Legacy.pdf")
    }

    func testDuplicateDeletedCaptureRecoversWithoutResettingMetadata() async throws {
        let library = store()
        _ = try await library.load()
        let input = try source("Duplicate.pdf", text: "Duplicate")
        let a = try await library.importPDF(from: input).document
        try await library.updateDocument(a.id, labels: [StarterLabel.work.id], reviewed: true)
        try await library.renameDocument(a.id, name: "Renamed")
        try await library.deleteDocument(a.id)
        let duplicate = try await library.importPDF(from: input)
        XCTAssertTrue(duplicate.isDuplicate)
        XCTAssertEqual(duplicate.document.id, a.id)
        XCTAssertEqual(duplicate.document.filename, "Renamed.pdf")
        XCTAssertEqual(duplicate.document.reviewState, .reviewed)
        XCTAssertEqual(duplicate.document.labelIDs, [StarterLabel.work.id])
        XCTAssertNil(duplicate.document.deletedAt)
    }
}
