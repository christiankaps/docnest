import XCTest
@testable import PdfPipe

@MainActor
final class ConfigurationAndExportTests: XCTestCase {
    func testTemplatesValidateAndDoNotReinterpretSourceTokens() throws {
        XCTAssertEqual(try FilenameTemplate.render("{original}_{text}", original: "report{date}", text: "Acme", date: Date()), "report{date}_Acme.pdf")
        XCTAssertThrowsError(try FilenameTemplate.render("{sender}", original: "file", text: "", date: Date()))
        XCTAssertThrowsError(try FilenameTemplate.render("{text}", original: "file", text: "", date: Date()))
        XCTAssertThrowsError(try FilenameTemplate.filename(".."))
        XCTAssertThrowsError(try FilenameTemplate.filename(String(repeating: "x", count: 181)))
        XCTAssertEqual(try FilenameTemplate.filename("invoice/2026:Acme.pdf"), "invoice_2026_Acme.pdf")
    }

    func testPipelinePersistenceExplicitDefaultAndDeletion() throws {
        let name = "PdfPipeTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let store = PipelineStore(defaults: defaults)
        let destination = Destination(bookmark: Data(), name: "Test")
        let pipeline = Pipeline(name: "Auto", steps: [.init(kind: .rename, template: "{original}")], destination: destination, unattended: true)
        try store.save(pipeline, isDefault: true)
        let reopened = PipelineStore(defaults: defaults)
        XCTAssertEqual(try reopened.configuration.defaultPipeline(), pipeline)
        try reopened.duplicate(pipeline)
        XCTAssertEqual(reopened.configuration.pipelines.count, 2)
        XCTAssertEqual(reopened.configuration.defaultID, pipeline.id)
        try reopened.delete(pipeline)
        XCTAssertNil(try reopened.configuration.defaultPipeline())
        XCTAssertEqual(reopened.configuration.pipelines.count, 1)
    }

    func testNoImplicitDefaultAndInvalidUnattendedConfiguration() throws {
        let pipeline = Pipeline(name: "Review")
        XCTAssertNil(try PipelineConfiguration(pipelines: [pipeline]).defaultPipeline())
        XCTAssertThrowsError(try PipelineConfiguration(pipelines: [pipeline], defaultID: pipeline.id).defaultPipeline())
        XCTAssertThrowsError(try Pipeline(unattended: true).validate())
        XCTAssertThrowsError(try Pipeline(steps: [.init(kind: .rename, template: "{text}")], destination: .init(bookmark: Data(), name: "Folder"), unattended: true).validate())
    }

    func testCorruptConfigurationIsNotOverwritten() throws {
        let name = "PdfPipeTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: name))
        defer { defaults.removePersistentDomain(forName: name) }
        let bad = Data("broken".utf8)
        defaults.set(bad, forKey: "pipelines.v1")
        let store = PipelineStore(defaults: defaults)
        XCTAssertNotNil(store.error)
        XCTAssertThrowsError(try store.save(Pipeline(), isDefault: false))
        XCTAssertEqual(defaults.data(forKey: "pipelines.v1"), bad)
    }

    func testDestinationSaveAvoidsCollisionsAndPreservesExistingFiles() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("destination")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let source = root.appendingPathComponent("result.pdf")
        try Data("new PDF bytes".utf8).write(to: source)
        let existing = folder.appendingPathComponent("result.pdf")
        try Data("existing".utf8).write(to: existing)
        let saved = try DestinationWriter.save(source, to: folder)
        XCTAssertEqual(saved.lastPathComponent, "result (2).pdf")
        XCTAssertEqual(try Data(contentsOf: saved), try Data(contentsOf: source))
        XCTAssertEqual(try Data(contentsOf: existing), Data("existing".utf8))
        let bookmark = try Destination.selected(folder)
        XCTAssertEqual(try bookmark.resolve().standardizedFileURL, folder.standardizedFileURL)
        let next = try DestinationWriter.save(source, destination: bookmark)
        XCTAssertEqual(next.lastPathComponent, "result (3).pdf")
    }

    func testMissingSourceCannotCreateAnEmptyDestination() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let missing = root.appendingPathComponent("missing.pdf")
        XCTAssertThrowsError(try DestinationWriter.save(missing, to: root))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertThrowsError(try DestinationWriter.save(missing, to: root.appendingPathComponent("absent")))
    }

    func testAbandonedCleanupProtectsLiveSessionsAndRemovesUnlockedOnes() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let live = try TemporarySession(root: root)
        let liveFile = live.directory.appendingPathComponent("document.pdf")
        try Data("private".utf8).write(to: liveFile)
        var abandoned: TemporarySession? = try TemporarySession(root: root)
        let old = try XCTUnwrap(abandoned?.directory)
        try Data("private".utf8).write(to: old.appendingPathComponent("document.pdf"))
        abandoned = nil
        try TemporarySession.removeAbandoned(root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: liveFile.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: old.path))
        XCTAssertEqual(try live.directory.resourceValues(forKeys: [.isExcludedFromBackupKey]).isExcludedFromBackup, true)
        try live.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: liveFile.path))
    }
}
