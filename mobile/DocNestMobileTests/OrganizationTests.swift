import XCTest
@testable import DocNestMobile

@MainActor
final class OrganizationTests: XCTestCase {
    private var sandbox: URL!
    private var root: URL { sandbox.appending(path: "Library") }
    private var snapshot: URL { root.appending(path: "organization.json") }

    override func setUp() async throws {
        sandbox = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }
    override func tearDown() async throws { try FileManager.default.removeItem(at: sandbox) }
    private func store(checkpoint: @escaping LibraryStore.Checkpoint = { _ in }) -> LibraryStore {
        LibraryStore(root: root, exportRoot: sandbox.appending(path: "Exports"), checkpoint: checkpoint)
    }
    private func source(_ name: String) throws -> URL {
        let url = sandbox.appending(path: "\(name).pdf")
        try DevelopmentFixtures.pdf(text: name, pages: 1).write(to: url)
        return url
    }
    private func date(_ year: Int) -> DocumentDate {
        DocumentDate(Calendar(identifier: .gregorian).date(from: DateComponents(year: year, month: 12, day: 31))!)
    }

    func testIncrementOneLibraryIsPreservedAndManualEditsSurviveDuplicateImport() async throws {
        let first = store()
        _ = try await first.load()
        let input = try source("Legacy")
        let imported = try await first.importPDF(from: input).document
        let folder = root.appending(path: "Documents/\(imported.id.uuidString)")
        let metadata = try Data(contentsOf: folder.appending(path: "metadata.json"))
        let bytes = try Data(contentsOf: input)
        // Increment 1 has these exact immutable import records and no organization snapshot.
        try FileManager.default.removeItem(at: snapshot)
        let upgraded = store()
        let loaded = try await upgraded.load()
        XCTAssertEqual(loaded, [imported])
        try await upgraded.updateDocument(imported.id, labels: [StarterLabel.invoices.id, StarterLabel.taxes.id], manualDate: date(2024), reviewed: true)
        let updated = try await upgraded.allDocuments().first!
        XCTAssertEqual(updated.dateSource, .manual)
        XCTAssertEqual(updated.reviewState, .reviewed)
        XCTAssertEqual(updated.documentDate.year, 2024)
        XCTAssertEqual(updated.importedAt, imported.importedAt)
        XCTAssertEqual(updated.filename, imported.filename)
        let duplicate = try await upgraded.importPDF(from: input)
        XCTAssertTrue(duplicate.isDuplicate)
        XCTAssertEqual(duplicate.document, updated)
        let reloaded = try await store().load()
        XCTAssertEqual(reloaded, [updated])
        XCTAssertEqual(try Data(contentsOf: folder.appending(path: "metadata.json")), metadata)
        XCTAssertEqual(try Data(contentsOf: folder.appending(path: "original.pdf")), bytes)
    }

    func testStarterIdentityCustomizationsAndAtomicLabelDeletionPersist() async throws {
        let library = store()
        _ = try await library.load()
        let starter = try await library.allLabels()
        XCTAssertEqual(Set(starter.map(\.id)), Set(StarterLabel.allCases.map(\.id)))
        XCTAssertEqual(starter.count, 10)
        let a = try await library.importPDF(from: source("One")).document
        let b = try await library.importPDF(from: source("Two")).document
        let custom = try await library.createLabel(name: "  Personal  ")
        XCTAssertEqual(custom.name, "Personal")
        try await library.updateDocument(a.id, labels: [custom.id, StarterLabel.taxes.id], reviewed: true)
        try await library.updateDocument(b.id, labels: [custom.id])
        try await library.renameLabel(StarterLabel.invoices.id, name: "Bills")
        try await library.deleteLabel(StarterLabel.banking.id)
        try await library.deleteLabel(custom.id)
        let relaunched = store()
        let documents = try await relaunched.load()
        let labels = try await relaunched.allLabels()
        XCTAssertEqual(labels.first { $0.id == StarterLabel.invoices.id }?.name, "Bills")
        XCTAssertFalse(labels.contains { $0.id == StarterLabel.banking.id })
        XCTAssertEqual(documents.count, 2)
        XCTAssertEqual(documents.first { $0.id == a.id }?.labelIDs, [StarterLabel.taxes.id])
        XCTAssertEqual(documents.first { $0.id == a.id }?.reviewState, .reviewed)
        XCTAssertEqual(documents.first { $0.id == b.id }?.labelIDs, [])
        for label in labels { try await relaunched.deleteLabel(label.id) }
        let empty = store()
        _ = try await empty.load()
        let emptyLabels = try await empty.allLabels()
        XCTAssertTrue(emptyLabels.isEmpty, "An intentionally empty starter set must never be reseeded")
    }

    func testANDYearFiltersSortingAndDoneWithoutLabels() async throws {
        let library = store()
        _ = try await library.load()
        let a = try await library.importPDF(from: source("A"), importedAt: date(2026).displayDate).document
        let b = try await library.importPDF(from: source("B"), importedAt: date(2020).displayDate).document
        let c = try await library.importPDF(from: source("C"), importedAt: date(2025).displayDate).document
        let invoices = StarterLabel.invoices.id, taxes = StarterLabel.taxes.id
        try await library.updateDocument(a.id, labels: [invoices, taxes], manualDate: date(2023))
        try await library.updateDocument(b.id, labels: [invoices], manualDate: date(2024))
        try await library.updateDocument(c.id, reviewed: true)
        let docs = try await library.allDocuments()
        XCTAssertEqual(docs.map(\.id), [c.id, b.id, a.id], "Sort by document date, not import time")
        var filter = LibraryFilter(labelIDs: [invoices, taxes])
        XCTAssertEqual(docs.filter(filter.includes).map(\.id), [a.id])
        filter.year = 2024
        XCTAssertTrue(docs.filter(filter.includes).isEmpty)
        filter.year = 2023
        XCTAssertEqual(docs.filter(filter.includes).map(\.id), [a.id])
        filter.year = nil
        filter.labelIDs.remove(taxes)
        XCTAssertEqual(docs.filter(filter.includes).map(\.id), [b.id, a.id])
        let reviewed = try XCTUnwrap(docs.first { $0.id == c.id })
        XCTAssertEqual(reviewed.dateSource, .importFallback, "Done does not confirm a fallback date")
        XCTAssertEqual(reviewed.reviewState, .reviewed)
        XCTAssertTrue(reviewed.labelIDs.isEmpty)
        let reload = try await store().load()
        XCTAssertEqual(reload, docs)
    }

    func testFailedMetadataWritePreservesPreviousSnapshotAndInterruptedWriteRecovery() async throws {
        let library = store()
        _ = try await library.load()
        let a = try await library.importPDF(from: source("A")).document
        try await library.updateDocument(a.id, labels: [StarterLabel.taxes.id])
        let before = try Data(contentsOf: snapshot)
        let failing = store { if $0 == .organizationWillWrite { throw CocoaError(.fileWriteOutOfSpace) } }
        let prior = try await failing.load()
        do { try await failing.deleteLabel(StarterLabel.taxes.id); XCTFail("Expected write failure") }
        catch { XCTAssertEqual((error as NSError).code, CocoaError.fileWriteOutOfSpace.rawValue) }
        let stillLoaded = try await failing.allDocuments()
        XCTAssertEqual(stillLoaded, prior)
        XCTAssertEqual(try Data(contentsOf: snapshot), before)
        // A terminated atomic write leaves its temporary file unpublished; only the committed path is read.
        try Data("partial JSON".utf8).write(to: root.appending(path: ".organization-unpublished"))
        let recovered = store()
        let docs = try await recovered.load()
        XCTAssertEqual(docs, prior)
        // A committed snapshot survives termination before the caller refreshes its UI.
        try await recovered.deleteLabel(StarterLabel.taxes.id)
        let committed = try await store().load()
        XCTAssertTrue(committed[0].labelIDs.isEmpty)
        XCTAssertEqual(committed[0].id, a.id)
    }

    func testInvalidInputsAndDamagedSnapshotsFailWithoutLosingData() async throws {
        let library = store()
        _ = try await library.load()
        let a = try await library.importPDF(from: source("Keep")).document
        let before = try Data(contentsOf: snapshot)
        for name in ["  ", "invoices", "Line\nBreak"] {
            do { try await library.createLabel(name: name); XCTFail("Invalid label accepted") }
            catch { XCTAssertEqual(error as? LibraryError, .invalidLabel) }
        }
        do { try await library.updateDocument(a.id, labels: [UUID()]); XCTFail("Unknown label accepted") }
        catch { XCTAssertEqual(error as? LibraryError, .invalidLabel) }
        let invalidDate = try JSONDecoder().decode(DocumentDate.self, from: Data("{\"year\":2024,\"month\":2,\"day\":30}".utf8))
        do { try await library.updateDocument(a.id, manualDate: invalidDate); XCTFail("Invalid date accepted") }
        catch { XCTAssertEqual(error as? LibraryError, .invalidDate) }
        XCTAssertEqual(try Data(contentsOf: snapshot), before)
        for data in [Data("broken".utf8), Data("{\"schemaVersion\":99}".utf8)] {
            try data.write(to: snapshot)
            do { _ = try await store().load(); XCTFail("Damaged/future snapshot accepted") }
            catch { XCTAssertTrue(error as? LibraryError == .invalidLibrary || error as? LibraryError == .unsupportedVersion) }
            XCTAssertEqual(try Data(contentsOf: snapshot), data)
        }
        try before.write(to: snapshot)
        let reloaded = try await store().load()
        XCTAssertEqual(reloaded, [a])
    }

    func testModelRefreshesOpenDocumentLabelsYearsAndInboxImmediately() async throws {
        let library = store()
        _ = try await library.load()
        let a = try await library.importPDF(from: source("Live")).document
        let model = LibraryModel(store: library)
        await model.load()
        XCTAssertEqual(model.inboxCount, 1)
        let saved = await model.save {
            try await library.updateDocument(a.id, labels: [StarterLabel.home.id], manualDate: self.date(2021), reviewed: true)
        }
        XCTAssertTrue(saved)
        XCTAssertEqual(model.document(a.id)?.documentDate.year, 2021)
        XCTAssertEqual(model.years, [2021])
        XCTAssertEqual(model.inboxCount, 0)
        XCTAssertEqual(model.labels(for: model.document(a.id)!).map(\.id), [StarterLabel.home.id])
    }
}
