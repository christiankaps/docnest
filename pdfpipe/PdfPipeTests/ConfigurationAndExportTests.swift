import XCTest
@testable import PdfPipe

@MainActor
final class ConfigurationAndExportTests: XCTestCase {
    func testDirectImportUsesOnlyPipelineWhenThereIsExactlyOne() {
        let first = Pipeline(name: "First")
        let second = Pipeline(name: "Second")
        XCTAssertNil(PipelineConfiguration().solePipelineID)
        XCTAssertEqual(PipelineConfiguration(pipelines: [first]).solePipelineID, first.id)
        XCTAssertNil(PipelineConfiguration(pipelines: [first, second]).solePipelineID)
    }

    func testNewPipelineRequestsDocumentNamingReview() {
        let pipeline = Pipeline()
        XCTAssertTrue(pipeline.needsAnalysis)
        XCTAssertEqual(pipeline.steps.first?.template, "{documentDate}_{word1}")
    }

    func testOCRSkipPreferenceDefaultsForExistingPipelinesAndPersists() throws {
        let legacy = Data("{\"id\":\"00000000-0000-0000-0000-000000000001\",\"kind\":\"ocr\",\"template\":\"{original}\"}".utf8)
        XCTAssertTrue(try JSONDecoder().decode(PipelineStep.self, from: legacy).skipExistingText)
        let configured = try Pipeline().configured(ocr: true, rename: false, template: "", save: false, skipExistingText: false)
        let decoded = try JSONDecoder().decode(Pipeline.self, from: JSONEncoder().encode(configured))
        XCTAssertEqual(decoded.steps.count, 1)
        XCTAssertFalse(try XCTUnwrap(decoded.steps.first).skipExistingText)
    }

    func testStepSwitchesProduceUniqueFixedOrderAndPreservePipelineIdentity() throws {
        let legacy = Pipeline(name: "Legacy", steps: [.init(kind: .rename, template: "First"),
            .init(kind: .ocr), .init(kind: .ocr), .init(kind: .rename, template: "Last")])
        let configured = try legacy.configured(ocr: true, rename: true,
            template: try XCTUnwrap(legacy.steps.last?.template), save: false)
        XCTAssertEqual(configured.id, legacy.id)
        XCTAssertEqual(configured.steps.map(\.kind), [.ocr, .rename])
        XCTAssertEqual(try configured.outputFilename(original: "Source", text: "", date: Date()), "Last.pdf")
        let disabled = try configured.configured(ocr: false, rename: false, template: "{invalid}", save: false)
        XCTAssertTrue(disabled.steps.isEmpty)
        XCTAssertEqual(try disabled.outputFilename(original: "Source", text: "", date: Date()), "Source.pdf")
    }

    func testSaveSwitchRequiresFolderAndDisablingItClearsAutomaticDefault() throws {
        XCTAssertThrowsError(try Pipeline().configured(ocr: false, rename: true, template: "{original}", save: true))
        let domain = "PdfPipeStepTests-\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: domain))
        defer { defaults.removePersistentDomain(forName: domain) }
        let store = PipelineStore(defaults: defaults)
        let original = Pipeline(destination: .init(bookmark: Data(), name: "Folder"), unattended: true)
        try store.save(original, isDefault: true)
        let disabled = try original.configured(ocr: true, rename: false, template: "", save: false)
        XCTAssertNil(disabled.destination)
        XCTAssertFalse(disabled.unattended)
        try store.save(disabled, isDefault: false)
        XCTAssertNil(PipelineStore(defaults: defaults).configuration.defaultID)
        let enabled = try original.configured(ocr: true, rename: false, template: "", save: true)
        XCTAssertEqual(enabled.destination, original.destination)
        XCTAssertTrue(enabled.unattended)
    }

    func testTemplatesValidateAndDoNotReinterpretSourceTokens() throws {
        XCTAssertEqual(try FilenameTemplate.render("{original}_{text}", original: "report{date}", text: "Acme", date: Date()), "report{date}_Acme.pdf")
        XCTAssertThrowsError(try FilenameTemplate.render("{sender}", original: "file", text: "", date: Date()))
        XCTAssertThrowsError(try FilenameTemplate.render("{text}", original: "file", text: "", date: Date()))
        XCTAssertThrowsError(try FilenameTemplate.filename(".."))
        XCTAssertThrowsError(try FilenameTemplate.filename(String(repeating: "x", count: 181)))
        XCTAssertEqual(try FilenameTemplate.filename("invoice/2026:Acme.pdf"), "invoice_2026_Acme.pdf")
    }

    func testStructuredTemplateKeepsLegacyMeaningAndDefersDocumentValues() throws {
        let template = "{date}_{documentDate}_{word1}_{original}_{text}"
        let parts = try FilenameTemplate.parse(template)
        XCTAssertEqual(FilenameTemplate.source(parts), template)
        XCTAssertTrue(FilenameTemplate.requiresAnalysis(template))
        let date = try XCTUnwrap(Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 12)))
        let values = NamingValues(original: "report{date}", manualText: "Final", processedAt: date,
            documentDate: "2026-10-05", words: ["Telekom"])
        XCTAssertEqual(try FilenameTemplate.render(template, values: values),
            "2026-10-12_2026-10-05_Telekom_report{date}_Final.pdf")
        XCTAssertEqual(try FilenameTemplate.render("{date}", original: "Source", text: "", date: date), "2026-10-12.pdf")
        XCTAssertThrowsError(try FilenameTemplate.render(template, values: .init(original: "Source", manualText: "Final", processedAt: date)))
        XCTAssertThrowsError(try FilenameTemplate.parse("{word4}"))
        XCTAssertThrowsError(try FilenameTemplate.parse("Broken}"))
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
