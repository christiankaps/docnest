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

    func testInteractiveNamingWaitsForSelectionAndUsesSessionOnlyWords() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourcePDF(root: root, text: "Invoice date 2026-10-05 Telekom Internet")
        let original = try Data(contentsOf: source)
        let domain = "PdfPipeSelectionTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PipelineStore(defaults: defaults)
        let pipeline = Pipeline(name: "Smart", steps: [.init(kind: .rename,
            template: "{documentDate}_{word1}_{word2}_{word3}")])
        try store.save(pipeline, isDefault: false)
        let model = DocumentSessionModel()
        model.pipelineID = pipeline.id
        model.importFile(source, store: store, autoRun: false)
        try await waitForIdle(model)
        model.run(pipeline)
        try await waitForIdle(model)
        XCTAssertTrue(model.awaitingNaming)
        XCTAssertFalse(model.processed)
        XCTAssertEqual(model.analysis?.date, .found("2026-10-05"))
        model.toggleWord("Telekom")
        XCTAssertEqual(try model.selectedFilenamePreview().get(), "2026-10-05_Telekom.pdf")
        model.confirmNaming()
        try await waitForIdle(model)
        XCTAssertNil(model.error)
        XCTAssertTrue(model.processed)
        XCTAssertEqual(model.filename, "2026-10-05_Telekom.pdf")
        XCTAssertEqual(try Data(contentsOf: try XCTUnwrap(model.document?.url)), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        XCTAssertEqual(store.configuration.pipelines.first?.steps.first?.template,
                       "{documentDate}_{word1}_{word2}_{word3}")
        model.discard()
    }

    func testUnattendedDocumentNamingSavesWithoutInput() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourcePDF(root: root, text: "Invoice date 2026-10-05 Telekom Internet")
        let original = try Data(contentsOf: source)
        let destinationURL = root.appendingPathComponent("saved")
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let domain = "PdfPipeAutoNaming-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PipelineStore(defaults: defaults)
        let pipeline = Pipeline(name: "Automatic naming", steps: [.init(kind: .rename,
            template: "{documentDate}_{word1}_{word2}")],
            destination: try Destination.selected(destinationURL), unattended: true)
        try store.save(pipeline, isDefault: true)
        let model = DocumentSessionModel()
        var finished = false
        model.onFinished = { finished = true }
        model.importFile(source, store: store, autoRun: true)
        try await waitForIdle(model)
        XCTAssertNil(model.error)
        XCTAssertTrue(finished)
        XCTAssertFalse(model.awaitingNaming)
        let savedName = try XCTUnwrap(model.savedName)
        XCTAssertTrue(savedName.hasPrefix("2026-10-05_"))
        XCTAssertEqual(try Data(contentsOf: destinationURL.appendingPathComponent(savedName)), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
    }

    func testUnattendedNamingNeedsReviewForAmbiguousDateAndMissingWords() async throws {
        let root = try temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try sourcePDF(root: root,
            text: "Invoice date 2026-10-05 Invoice date 2026-10-06")
        let destinationURL = root.appendingPathComponent("saved")
        try FileManager.default.createDirectory(at: destinationURL, withIntermediateDirectories: true)
        let domain = "PdfPipeAutoNaming-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PipelineStore(defaults: defaults)
        let pipeline = Pipeline(name: "Ambiguous", steps: [.init(kind: .rename,
            template: "{documentDate}_{word1}")], destination: try Destination.selected(destinationURL), unattended: true)
        try store.save(pipeline, isDefault: true)
        let model = DocumentSessionModel()
        model.importFile(source, store: store, autoRun: true)
        try await waitForIdle(model)
        XCTAssertTrue(model.awaitingNaming)
        XCTAssertFalse(model.processed)
        XCTAssertNotNil(model.error)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destinationURL.path), [])
        model.selectedDate = "2026-10-05"
        model.manualKeyword = "Rechnung"
        model.addManualKeyword()
        model.error = nil
        model.confirmNaming()
        try await waitForIdle(model)
        XCTAssertTrue(model.processed)
        XCTAssertNil(model.error)
        XCTAssertNil(model.savedName, "Correction requires an explicit save")
        model.discard()

        let shortSource = try sourcePDF(root: root, text: "Alpha")
        let short = Pipeline(name: "Needs words", steps: [.init(kind: .rename,
            template: "{documentDate}_{word3}")], destination: try Destination.selected(destinationURL), unattended: true)
        try store.save(short, isDefault: true)
        let second = DocumentSessionModel()
        second.importFile(shortSource, store: store, autoRun: true)
        try await waitForIdle(second)
        XCTAssertTrue(second.awaitingNaming)
        XCTAssertNotNil(second.error)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: destinationURL.path), [])
        second.discard()
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

    private func sourcePDF(root: URL, text: String = "Synthetic invoice") throws -> URL {
        let source = root.appendingPathComponent("source.pdf")
        try UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792)).writePDF(to: source) { context in
            context.beginPage()
            text.draw(at: CGPoint(x: 50, y: 70), withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
        }
        return source
    }
}
