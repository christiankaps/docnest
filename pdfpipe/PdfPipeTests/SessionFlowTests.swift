import XCTest
import UIKit
@testable import PdfPipe

@MainActor
final class SessionFlowTests: XCTestCase {
    func testUnattendedImportSavesCleansAndFinishesWithoutUserInput() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourcePDF(root: root)
        let original = try Data(contentsOf: source)
        let destination = root.appendingPathComponent("saved")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let domain = "PdfPipeSessionTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PipelineStore(defaults: defaults)
        let pipeline = Pipeline(name: "Automatic", steps: [.init(kind: .rename, template: "Ready_{original}")],
                                destination: try Destination.selected(destination), unattended: true)
        try store.save(pipeline, isDefault: true)
        let model = DocumentSessionModel()
        var finished = false
        model.onFinished = { finished = true }
        model.importFile(source, store: store, autoRun: true)
        try await waitForIdle(model)
        XCTAssertNil(model.error)
        XCTAssertTrue(finished, "Successful unattended processing must finish the host request without a Done tap")
        XCTAssertEqual(model.savedName, "Ready_source.pdf")
        XCTAssertNil(model.document)
        XCTAssertEqual(try Data(contentsOf: destination.appendingPathComponent("Ready_source.pdf")), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testFailedAutomaticSaveRetainsResultForAlternateDestination() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourcePDF(root: root)
        let original = try Data(contentsOf: source)
        let unavailable = root.appendingPathComponent("unavailable")
        try FileManager.default.createDirectory(at: unavailable, withIntermediateDirectories: true)
        let bookmark = try Destination.selected(unavailable)
        try FileManager.default.removeItem(at: unavailable)
        let domain = "PdfPipeSessionTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PipelineStore(defaults: defaults)
        try store.save(Pipeline(name: "Automatic", steps: [.init(kind: .rename, template: "Ready")], destination: bookmark, unattended: true), isDefault: true)
        let model = DocumentSessionModel()
        var finished = false
        model.onFinished = { finished = true }
        model.importFile(source, store: store, autoRun: true)
        try await waitForIdle(model)
        XCTAssertNotNil(model.error)
        XCTAssertFalse(finished)
        XCTAssertTrue(model.processed)
        let retained = try XCTUnwrap(model.document?.url)
        XCTAssertTrue(FileManager.default.fileExists(atPath: retained.path))
        XCTAssertNil(model.savedName)
        let fallback = root.appendingPathComponent("fallback")
        try FileManager.default.createDirectory(at: fallback, withIntermediateDirectories: true)
        model.error = nil
        model.save(try Destination.selected(fallback))
        try await waitForIdle(model)
        XCTAssertNil(model.error)
        XCTAssertEqual(try Data(contentsOf: fallback.appendingPathComponent("Ready.pdf")), original)
        XCTAssertFalse(FileManager.default.fileExists(atPath: retained.path))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testDirectImportRequiresSelectionEvenWithUnattendedDefault() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourcePDF(root: root)
        let domain = "PdfPipeSessionTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PipelineStore(defaults: defaults)
        try store.save(Pipeline(name: "Automatic", destination: try Destination.selected(root), unattended: true), isDefault: true)
        let model = DocumentSessionModel()
        model.importFile(source, store: store, autoRun: false)
        try await waitForIdle(model)
        XCTAssertNotNil(model.document)
        XCTAssertNil(model.pipelineID)
        XCTAssertFalse(model.processed)
        XCTAssertNil(model.savedName)
        let copy = try XCTUnwrap(model.document?.url)
        var finished = false
        var finishCount = 0
        model.onFinished = { finished = true; finishCount += 1 }
        model.discard()
        model.discard()
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(finished)
        await Task.yield()
        XCTAssertEqual(finishCount, 1, "A racing discard must finish the host request only once")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: source.path))
    }

    func testDirectImportRetainsChosenPipelineWithoutRunningDefault() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourcePDF(root: root)
        let domain = "PdfPipeSelectionTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PipelineStore(defaults: defaults)
        try store.save(Pipeline(name: "Automatic", destination: try Destination.selected(root), unattended: true), isDefault: true)
        let selected = Pipeline(name: "Chosen", steps: [.init(kind: .rename, template: "Chosen_{original}")])
        try store.save(selected, isDefault: false)
        let model = DocumentSessionModel()
        model.pipelineID = selected.id
        model.importFile(source, store: store, autoRun: false)
        try await waitForIdle(model)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.pipelineID, selected.id)
        XCTAssertFalse(model.processed)
        XCTAssertNil(model.savedName)
        XCTAssertEqual(try model.filenamePreview(selected).get(), "Chosen_source.pdf")
        var finished = false
        model.onFinished = { finished = true }
        model.discard()
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(finished)
    }

    func testProviderImportPreservesSuppliedFilenameAndCopiesInput() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourcePDF(root: root)
        let original = try Data(contentsOf: source)
        let domain = "PdfPipeSessionTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let provider = try XCTUnwrap(NSItemProvider(contentsOf: source))
        provider.suggestedName = "Supplied invoice.pdf"
        let model = DocumentSessionModel()
        model.importProvider(provider, store: PipelineStore(defaults: defaults))
        try await waitForIdle(model)
        XCTAssertNil(model.error)
        XCTAssertEqual(model.document?.facts.filename, "Supplied invoice.pdf")
        XCTAssertEqual(try Data(contentsOf: source), original)
        let copy = try XCTUnwrap(model.document?.url)
        XCTAssertNotEqual(copy, source)
        var finished = false
        var finishCount = 0
        model.onFinished = { finished = true; finishCount += 1 }
        model.discard()
        model.discard()
        let deadline = Date().addingTimeInterval(5)
        while !finished && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertTrue(finished)
        await Task.yield()
        XCTAssertEqual(finishCount, 1, "A racing discard must finish the host request only once")
        XCTAssertFalse(FileManager.default.fileExists(atPath: copy.path))
    }

    private func waitForIdle(_ model: DocumentSessionModel) async throws {
        let deadline = Date().addingTimeInterval(10)
        while model.busy && Date() < deadline { try await Task.sleep(for: .milliseconds(20)) }
        XCTAssertFalse(model.busy, model.error ?? model.progress)
    }

    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    private func sourcePDF(root: URL) throws -> URL {
        let source = root.appendingPathComponent("source.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: source) { context in
            context.beginPage()
            "Synthetic invoice".draw(at: CGPoint(x: 50, y: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        return source
    }
}
