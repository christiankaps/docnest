import XCTest
import UIKit
@testable import PdfPipe

@MainActor
final class ReviewRegressionTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func writePDF(_ url: URL) throws {
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: url) { context in
            context.beginPage()
            "Review fixture".draw(at: CGPoint(x: 50, y: 50), withAttributes: [.font: UIFont.systemFont(ofSize: 20)])
        }
    }

    private func waitUntil(_ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(5)
        while !condition() && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(condition())
    }

    func testInboxDeliveryConsumedOnSuccessFailureAndCancellation() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let domain = "PdfPipeInboxTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        for scenario in ["success", "failure", "cancel"] {
            let source = inbox.appendingPathComponent("Review-\(UUID()).pdf")
            defer { try? FileManager.default.removeItem(at: source) }
            if scenario == "failure" { try Data("not a PDF".utf8).write(to: source) }
            else { try writePDF(source) }
            let model = DocumentSessionModel(inboxDirectory: inbox)
            model.importFile(source, store: PipelineStore(defaults: defaults), autoRun: false)
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path), "Claim the app-owned delivery before asynchronous work")
            XCTAssertEqual(try root.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
            if scenario != "cancel" {
                try await waitUntil { !model.busy }
                if scenario == "success" {
                    XCTAssertNil(model.error)
                    XCTAssertEqual(model.document?.facts.filename, source.lastPathComponent)
                } else { XCTAssertNotNil(model.error) }
            }
            let copy = model.document?.url
            var finished = false
            model.onFinished = { finished = true }
            model.discard()
            try await waitUntil { finished }
            if let copy { XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path)) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: source.path))
        }
    }

    func testRealDocumentsDirectoryCanBeExcludedWithoutWritingInbox() throws {
        try InboxDelivery.excludeFromBackup()
        let documents = InboxDelivery.directory.deletingLastPathComponent()
        XCTAssertEqual(try documents.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
    }

    func testInboxCleanupPreservesExternalOriginalsAndReclaimsInterruptedDelivery() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let inbox = root.appendingPathComponent("Inbox")
        try FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
        let original = root.appendingPathComponent("original.pdf")
        try writePDF(original)
        let bytes = try Data(contentsOf: original)
        let sessions = root.appendingPathComponent("sessions")
        var session: TemporarySession? = try TemporarySession(root: sessions)
        let directory = try XCTUnwrap(session?.directory)
        XCTAssertEqual(try InboxDelivery.claim(original, into: directory, inbox: inbox), original)
        try InboxDelivery.discard(original, inbox: inbox)
        let link = inbox.appendingPathComponent("link.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: original)
        XCTAssertThrowsError(try InboxDelivery.claim(link, into: directory, inbox: inbox))
        try InboxDelivery.discard(link, inbox: inbox)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        let delivered = inbox.appendingPathComponent("delivered.pdf")
        try bytes.write(to: delivered)
        let claimed = try InboxDelivery.claim(delivered, into: directory, inbox: inbox)
        XCTAssertEqual(try Data(contentsOf: claimed), bytes)
        XCTAssertFalse(FileManager.default.fileExists(atPath: delivered.path))
        session = nil // Simulate the lifetime lock being released by process exit.
        try TemporarySession.removeAbandoned(root: sessions)
        XCTAssertFalse(FileManager.default.fileExists(atPath: claimed.path))
        try bytes.write(to: inbox.appendingPathComponent("rejected.pdf"))
        try InboxDelivery.removeUnclaimed(inbox: inbox)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: inbox.path).isEmpty)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        XCTAssertFalse(InboxDelivery.owns(root.appendingPathComponent("Inbox-other/file.pdf"), inbox: inbox))
    }

    func testLongSourceNameImportsAndCanBeRenamedToShortName() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let name = String(repeating: "a", count: 200) + ".pdf"
        let source = root.appendingPathComponent(name)
        try writePDF(source)
        let original = try Data(contentsOf: source)
        let session = try TemporarySession(root: root.appendingPathComponent("sessions"))
        defer { try? session.cleanup() }
        let engine = DocumentEngine(session: session)
        let staged = try DocumentEngine.stage(source, to: session.directory)
        let input = try await engine.prepare(staged: staged, originalName: name)
        XCTAssertEqual(input.facts.filename, name)
        let pipeline = Pipeline(steps: [.init(kind: .rename, template: "Short")])
        let result = try await engine.process(pipeline, text: "") { _ in }
        XCTAssertEqual(result.facts.filename, "Short.pdf")
        XCTAssertEqual(try Data(contentsOf: result.url), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        // Output limits still apply when no rename fixes the long input name.
        do {
            _ = try await engine.process(Pipeline(steps: [.init(kind: .ocr)]), text: "") { _ in }
            XCTFail("Expected filename validation before OCR")
        } catch { XCTAssertTrue(error.localizedDescription.contains("too long")) }
        XCTAssertFalse(try FileManager.default.contentsOfDirectory(atPath: session.directory.path).contains { $0.hasPrefix("ocr-") })
    }

    func testPreviewTracksManualTextAndMatchesExecutionIncludingStepOrder() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("Invoice.pdf")
        try writePDF(source)
        let session = try TemporarySession(root: root.appendingPathComponent("sessions"))
        defer { try? session.cleanup() }
        let engine = DocumentEngine(session: session)
        let staged = try DocumentEngine.stage(source, to: session.directory)
        let model = DocumentSessionModel()
        model.document = try await engine.prepare(staged: staged, originalName: source.lastPathComponent)
        let date = Date(timeIntervalSince1970: 1_792_000_000)
        let pipeline = Pipeline(steps: [.init(kind: .rename, template: "First"),
                                       .init(kind: .rename, template: "{date}_{original}_{text}")])
        XCTAssertThrowsError(try model.filenamePreview(pipeline, date: date).get())
        model.manualText = "Acme"
        let preview = try model.filenamePreview(pipeline, date: date).get()
        XCTAssertTrue(preview.hasSuffix("_Invoice_Acme.pdf"))
        let result = try await engine.process(pipeline, text: model.manualText, date: date) { _ in }
        XCTAssertEqual(result.facts.filename, preview)
        model.manualText = "Other"
        XCTAssertTrue(try model.filenamePreview(pipeline, date: date).get().hasSuffix("_Invoice_Other.pdf"))
        XCTAssertEqual(try model.filenamePreview(Pipeline(steps: []), date: date).get(), "Invoice.pdf")
        XCTAssertThrowsError(try model.filenamePreview(Pipeline(steps: [.init(kind: .rename, template: "{unknown}")]), date: date).get())
        model.manualText = String(repeating: "x", count: 200)
        XCTAssertThrowsError(try model.filenamePreview(pipeline, date: date).get())
    }

    func testSavePublishesOnlyCompleteBytesAndHandlesCollisionAtCommit() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("result.pdf")
        let bytes = Data(repeating: 42, count: 700_000)
        try bytes.write(to: source)
        let folder = root.appendingPathComponent("saved")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let collision = folder.appendingPathComponent("result.pdf")
        var chunks = 0
        let saved = try DestinationWriter.save(source, to: folder) {
            chunks += 1
            let entries = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            XCTAssertEqual(entries.filter { $0.pathExtension == "partial" }.count, 1)
            XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("result (2).pdf").path))
            if chunks == 1 {
                XCTAssertFalse(FileManager.default.fileExists(atPath: collision.path))
                try Data("another writer".utf8).write(to: collision)
            }
        }
        XCTAssertGreaterThan(chunks, 1)
        XCTAssertEqual(saved.lastPathComponent, "result (2).pdf")
        XCTAssertEqual(try Data(contentsOf: saved), bytes)
        XCTAssertEqual(try Data(contentsOf: collision), Data("another writer".utf8))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: folder.path).count, 2)
    }

    func testFailedOrCanceledWritePublishesNothingAndRemovesStaging() throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("result.pdf")
        let bytes = Data(repeating: 42, count: 700_000)
        try bytes.write(to: source)
        let folder = root.appendingPathComponent("saved")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for failure: Error in [CancellationError(), POSIXError(.ENOSPC)] {
            XCTAssertThrowsError(try DestinationWriter.save(source, to: folder) {
                XCTAssertFalse(FileManager.default.fileExists(atPath: folder.appendingPathComponent("result.pdf").path))
                throw failure
            })
            XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: folder.path).isEmpty)
            XCTAssertEqual(try Data(contentsOf: source), bytes)
        }
    }
}
