import LocalAuthentication
import PDFKit
import XCTest
@testable import DocNestMobile

@MainActor
final class PrivacyTests: XCTestCase {
    private var sandbox: URL!
    private var defaults: UserDefaults!
    private var suite: String!
    override func setUp() async throws {
        sandbox = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
        suite = "DocNest.PrivacyTests.\(UUID())"
        defaults = UserDefaults(suiteName: suite)!
    }
    override func tearDown() async throws {
        defaults.removePersistentDomain(forName: suite)
        try FileManager.default.removeItem(at: sandbox)
    }
    private func source(_ name: String = "Private.pdf", text: String = "Private") throws -> URL {
        let url = sandbox.appending(path: name)
        try DevelopmentFixtures.pdf(text: text, pages: 1).write(to: url)
        return url
    }
    private func library(policy: LibraryAccessPolicy = LibraryAccessPolicy(), checkpoint: @escaping LibraryStore.Checkpoint = { _ in }) -> LibraryStore {
        LibraryStore(root: sandbox.appending(path: "Library"), exportRoot: sandbox.appending(path: "Exports"), checkpoint: checkpoint, accessPolicy: policy)
    }
    private func expectLocked(_ action: () async throws -> Void, file: StaticString = #filePath, line: UInt = #line) async {
        do { try await action(); XCTFail("Protected access succeeded", file: file, line: line) }
        catch { XCTAssertEqual(error as? LibraryError, .libraryLocked, file: file, line: line) }
    }

    func testEnableDisableColdLaunchAndNoGracePeriod() async throws {
        let auth = TestAuthenticator()
        let lock = LibraryLockController(defaults: defaults, authenticator: auth)
        XCTAssertFalse(lock.isEnabled)
        let enabled = await lock.setEnabled(true)
        XCTAssertTrue(enabled)
        XCTAssertTrue(lock.isEnabled)
        XCTAssertFalse(lock.isLocked)
        lock.activityChanged(.inactive)
        XCTAssertFalse(lock.isLocked, "Transient inactivity does not invalidate the session")
        lock.activityChanged(.active)
        lock.beginSystemTask()
        lock.activityChanged(.background)
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.policy.isLocked)
        XCTAssertEqual(lock.systemTaskCount, 1, "A native task must not be cancelled by relocking")
        lock.activityChanged(.active)
        XCTAssertTrue(lock.isLocked, "Foreground does not authenticate implicitly")
        let unlocked = await lock.unlock()
        XCTAssertTrue(unlocked)
        XCTAssertFalse(lock.isLocked)
        lock.endSystemTask()
        XCTAssertEqual(lock.systemTaskCount, 0)
        let reopened = LibraryLockController(defaults: defaults, authenticator: auth)
        XCTAssertTrue(reopened.isLocked, "Relaunch never restores an authenticated session")
        let disabled = await reopened.setEnabled(false)
        XCTAssertTrue(disabled)
        XCTAssertFalse(LibraryLockController(defaults: defaults, authenticator: auth).isEnabled)
        XCTAssertEqual(auth.reasons.count, 3, "Enabling, unlocking, and disabling require device-owner authentication")
    }

    func testFailureAndStaleAuthenticationNeverUnlockOrEnable() async throws {
        let auth = TestAuthenticator()
        auth.failure = LAError(.passcodeNotSet)
        let lock = LibraryLockController(defaults: defaults, authenticator: auth)
        let failed = await lock.setEnabled(true)
        XCTAssertFalse(failed)
        XCTAssertFalse(lock.isEnabled)
        XCTAssertNotNil(lock.authenticationError)
        auth.failure = nil
        auth.suspended = true
        let enablingStarted = expectation(description: "Enable authentication started")
        auth.onStart = { enablingStarted.fulfill() }
        let enabling = Task { await lock.setEnabled(true) }
        await fulfillment(of: [enablingStarted], timeout: 2)
        guard auth.pending != nil else { XCTFail("Authentication did not reach its barrier"); return }
        lock.activityChanged(.background)
        auth.complete()
        let stale = await enabling.value
        XCTAssertFalse(stale)
        XCTAssertFalse(defaults.bool(forKey: "libraryLockEnabled"))
        lock.activityChanged(.active)
        auth.suspended = false
        auth.onStart = nil
        _ = await lock.setEnabled(true)
        lock.activityChanged(.background)
        lock.activityChanged(.active)
        auth.suspended = true
        let unlockingStarted = expectation(description: "Unlock authentication started")
        auth.onStart = { unlockingStarted.fulfill() }
        let unlocking = Task { await lock.unlock() }
        await fulfillment(of: [unlockingStarted], timeout: 2)
        guard auth.pending != nil else { XCTFail("Authentication did not reach its barrier"); return }
        lock.activityChanged(.background)
        lock.activityChanged(.active)
        auth.complete()
        let oldUnlock = await unlocking.value
        XCTAssertFalse(oldUnlock)
        XCTAssertTrue(lock.isLocked)
        XCTAssertTrue(lock.policy.isLocked)
        XCTAssertGreaterThanOrEqual(auth.cancellations, 3)
    }

    func testLockedStoreRejectsEveryProtectedEntryPointButAllowsExportCleanup() async throws {
        let policy = LibraryAccessPolicy()
        let store = library(policy: policy)
        _ = try await store.load()
        let input = try source()
        let doc = try await store.importPDF(from: input).document
        let copy = try await store.exportCopy(for: doc.id)
        let snapshot = try Data(contentsOf: sandbox.appending(path: "Library/organization.json"))
        policy.setLocked(true)
        await expectLocked { _ = try await store.load() }
        await expectLocked { _ = try await store.allDocuments() }
        await expectLocked { _ = try await store.allLabels() }
        await expectLocked { _ = try await store.recentlyDeleted() }
        await expectLocked { _ = try await store.originalURL(for: doc.id) }
        await expectLocked { _ = try await store.search(document: doc.id, text: "Private") }
        await expectLocked { _ = try await store.exportCopies(for: [doc.id]) }
        await expectLocked { _ = try await store.exportCopy(for: doc.id) }
        await expectLocked { _ = try await store.importPDF(from: input) }
        await expectLocked { _ = try await store.createLabel(name: "New") }
        await expectLocked { try await store.renameLabel(StarterLabel.home.id, name: "New") }
        await expectLocked { try await store.deleteLabel(StarterLabel.home.id) }
        await expectLocked { try await store.updateDocument(doc.id, reviewed: true) }
        await expectLocked { try await store.renameDocument(doc.id, name: "New") }
        await expectLocked { try await store.addLabels([StarterLabel.home.id], to: [doc.id]) }
        await expectLocked { try await store.deleteDocument(doc.id) }
        await expectLocked { try await store.recover(doc.id) }
        await expectLocked { try await store.cleanupExpired() }
        await store.removeExport(copy)
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertEqual(try Data(contentsOf: sandbox.appending(path: "Library/organization.json")), snapshot)
        policy.setLocked(false)
        let restored = try await store.load()
        XCTAssertEqual(restored, [doc])
    }

    func testLockedCaptureIsDurableGenericAndDrainsUsingOriginalImportRules() async throws {
        let lock = LibraryLockController(defaults: defaults, authenticator: TestAuthenticator())
        let store = library(policy: lock.policy)
        _ = try await store.load()
        let input = try source("Invoice.pdf", text: "Existing")
        let doc = try await store.importPDF(from: input).document
        try await store.updateDocument(doc.id, labels: [StarterLabel.home.id], reviewed: true)
        let before = try Data(contentsOf: sandbox.appending(path: "Library/organization.json"))
        _ = await lock.setEnabled(true)
        lock.activityChanged(.background)
        lock.activityChanged(.active)
        let queueRoot = sandbox.appending(path: "Capture")
        let queue = CaptureInbox(root: queueRoot)
        let model = LibraryModel(store: store, access: lock, captures: queue)
        await model.importPDF(input)
        XCTAssertNil(model.duplicate)
        XCTAssertTrue(model.documents.isEmpty)
        XCTAssertEqual(lock.captureNotice, "PDF saved. Unlock your library to review it.")
        XCTAssertEqual(try Data(contentsOf: sandbox.appending(path: "Library/organization.json")), before)
        let newInput = try source("Invoice.pdf", text: "New")
        let capturedAt = Date(timeIntervalSinceReferenceDate: 800_000_000)
        _ = try await queue.acceptPDF(from: newInput, capturedAt: capturedAt)
        let reopenedQueue = CaptureInbox(root: queueRoot)
        await expectLocked { _ = try await reopenedQueue.drain(into: store) }
        _ = await lock.unlock()
        await model.load()
        let results = try await reopenedQueue.drain(into: store)
        XCTAssertEqual(results.count, 2)
        let duplicate = try XCTUnwrap(results.first { $0.isDuplicate })
        XCTAssertEqual(duplicate.document.id, doc.id)
        XCTAssertEqual(duplicate.document.reviewState, .reviewed)
        XCTAssertEqual(duplicate.document.labelIDs, [StarterLabel.home.id])
        let added = try XCTUnwrap(results.first { !$0.isDuplicate })
        XCTAssertEqual(added.document.filename, "Invoice_2.pdf")
        XCTAssertEqual(added.document.importedAt, capturedAt)
        let pending = try FileManager.default.contentsOfDirectory(at: queueRoot.appending(path: "Pending"), includingPropertiesForKeys: nil)
        XCTAssertTrue(pending.isEmpty)
    }

    func testRestrictedCaptureCannotReadLiveLibraryOrPrivateAliases() async throws {
        let policy = LibraryAccessPolicy()
        let store = library(policy: policy)
        _ = try await store.load()
        let doc = try await store.importPDF(from: source()).document
        let original = try await store.originalURL(for: doc.id)
        let queue = CaptureInbox(root: sandbox.appending(path: "Capture"), protectedLibraryRoots: [sandbox.appending(path: "Library")])
        let alias = sandbox.appending(path: "Alias.pdf")
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: original)
        policy.setLocked(true)
        for input in [original, alias] {
            do { _ = try await queue.acceptPDF(from: input); XCTFail("Private original was captured while locked") }
            catch { XCTAssertEqual(error as? LibraryError, .invalidCaptureSource) }
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: sandbox.appending(path: "Capture").path))
    }

    func testRelockingDuringDrainPreservesRemainingCaptureAndHidesResults() async throws {
        let policy = LibraryAccessPolicy()
        let store = library(policy: policy, checkpoint: { if $0 == .metadataWritten { policy.setLocked(true) } })
        _ = try await store.load()
        let root = sandbox.appending(path: "Capture")
        let queue = CaptureInbox(root: root)
        _ = try await queue.acceptPDF(from: source("One.pdf", text: "One"))
        _ = try await queue.acceptPDF(from: source("Two.pdf", text: "Two"))
        await expectLocked { _ = try await queue.drain(into: store) }
        let retained = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Pending"), includingPropertiesForKeys: nil)
        XCTAssertEqual(retained.count, 1)
        policy.setLocked(false)
        let reopened = library(policy: policy)
        let first = try await reopened.load()
        XCTAssertEqual(first.count, 1, "Work authorized before relocking may finish its transaction")
        let remaining = try await CaptureInbox(root: root).drain(into: reopened)
        XCTAssertEqual(remaining.count, 1)
        let all = try await reopened.allDocuments()
        XCTAssertEqual(all.count, 2)
    }

    func testEncryptedAndCorruptPendingCaptureFailWithoutDiscardingFiles() async throws {
        let root = sandbox.appending(path: "Capture")
        let queue = CaptureInbox(root: root)
        let pdf = try XCTUnwrap(PDFDocument(data: DevelopmentFixtures.pdf(text: "Encrypted", pages: 1)))
        let encrypted = sandbox.appending(path: "Encrypted.pdf")
        XCTAssertTrue(pdf.write(to: encrypted, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: "secret"]))
        do { _ = try await queue.acceptPDF(from: encrypted); XCTFail() } catch { XCTAssertEqual(error as? LibraryError, .encryptedPDF) }
        let receipt = try await queue.acceptPDF(from: source())
        let manifest = root.appending(path: "Pending/\(receipt.id.uuidString)/capture.json")
        try Data("broken".utf8).write(to: manifest)
        let store = library()
        _ = try await store.load()
        do { _ = try await queue.drain(into: store); XCTFail() } catch { XCTAssertEqual(error as? LibraryError, .invalidCapture) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: manifest.path))
        let records = try await store.allDocuments()
        XCTAssertTrue(records.isEmpty)
    }

    func testCaptureRejectionAndInterruptedDrainKeepLastValidLibrary() async throws {
        let root = sandbox.appending(path: "Capture")
        let queue = CaptureInbox(root: root)
        let bad = sandbox.appending(path: "Bad.pdf")
        try Data("Not a PDF".utf8).write(to: bad)
        do { _ = try await queue.acceptPDF(from: bad); XCTFail() } catch { XCTAssertEqual(error as? LibraryError, .invalidPDF) }
        let stages = try FileManager.default.contentsOfDirectory(at: root.appending(path: "Staging"), includingPropertiesForKeys: nil)
        XCTAssertTrue(stages.isEmpty)
        let good = try source()
        _ = try await queue.acceptPDF(from: good)
        let initial = library()
        _ = try await initial.load()
        let failing = library(checkpoint: { if $0 == .metadataWritten { throw CocoaError(.fileWriteOutOfSpace) } })
        _ = try await failing.load()
        do { _ = try await queue.drain(into: failing); XCTFail() } catch { }
        let retry = CaptureInbox(root: root)
        let results = try await retry.drain(into: initial)
        XCTAssertEqual(results.count, 1)
        // Recreate a queued copy after a committed import, as if termination preceded queue removal.
        _ = try await retry.acceptPDF(from: good)
        let duplicates = try await CaptureInbox(root: root).drain(into: initial)
        XCTAssertTrue(duplicates[0].isDuplicate)
        let docs = try await initial.allDocuments()
        XCTAssertEqual(docs.count, 1)
    }
}

@MainActor
private final class TestAuthenticator: LibraryAuthenticating {
    var failure: Error?
    var suspended = false
    var pending: CheckedContinuation<Void, Error>?
    var reasons: [String] = []
    var cancellations = 0
    var onStart: (() -> Void)?
    func authenticate(reason: String) async throws {
        reasons.append(reason)
        onStart?()
        if let failure { throw failure }
        if suspended { try await withCheckedThrowingContinuation { pending = $0 } }
    }
    func cancel() { cancellations += 1 }
    func complete() { pending?.resume(); pending = nil }
}
