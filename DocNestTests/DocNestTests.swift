import XCTest
import SwiftData
import PDFKit
@testable import DocNest

private enum TestSampleDataSeeder {
    @MainActor
    static func seedIfNeeded(using context: ModelContext) throws {
        let descriptor = FetchDescriptor<DocumentRecord>()
        let existingCount = try context.fetchCount(descriptor)
        guard existingCount == 0 else { return }

        let labels = LabelTag.makeSamples()
        context.insert(labels.finance)
        context.insert(labels.tax)
        context.insert(labels.contracts)

        let documents = DocumentRecord.makeSamples(labels: labels)
        for document in documents {
            context.insert(document)
        }

        try context.save()
    }
}

final class DocNestTests: XCTestCase {
    override func tearDown() {
        super.tearDown()
        DocumentLibraryService.persistLibraryURL(nil)
    }

    @MainActor
    func testSampleDataCanBeSeeded() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, configurations: config)
        let context = container.mainContext

        try TestSampleDataSeeder.seedIfNeeded(using: context)

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documents.count, 3)

        let labels = try context.fetch(FetchDescriptor<LabelTag>())
        XCTAssertEqual(labels.count, 3)
    }

    @MainActor
    func testSeedingIsIdempotent() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, configurations: config)
        let context = container.mainContext

        try TestSampleDataSeeder.seedIfNeeded(using: context)
        try TestSampleDataSeeder.seedIfNeeded(using: context)

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documents.count, 3, "Seeding should not duplicate data on second call")
    }

    @MainActor
    func testDocumentRecordAcceptsStoredFilePath() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, configurations: config)
        let context = container.mainContext

        let doc = DocumentRecord(
            originalFileName: "test.pdf",
            title: "Test",
            sourceCreatedAt: .now.addingTimeInterval(-86_400),
            importedAt: .now,
            pageCount: 1,
            fileSize: 8_192,
            contentHash: "abc123",
            storedFilePath: "/tmp/test-path.pdf"
        )
        context.insert(doc)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(fetched.first?.storedFilePath, "/tmp/test-path.pdf")
        XCTAssertEqual(fetched.first?.fileSize, 8_192)
        XCTAssertEqual(fetched.first?.contentHash, "abc123")
    }

    func testCreateLibraryCreatesRequiredStructure() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Test Library")

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let createdLibraryURL = try DocumentLibraryService.createLibrary(at: libraryURL)

        XCTAssertEqual(createdLibraryURL.pathExtension, DocumentLibraryService.packageExtension)
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdLibraryURL.appendingPathComponent("Metadata", isDirectory: true).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdLibraryURL.appendingPathComponent("Originals", isDirectory: true).path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: createdLibraryURL.appendingPathComponent("Metadata/library.json").path))
    }

    func testValidateLibraryRejectsMissingManifest() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Broken Library.docnestlibrary", isDirectory: true)

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        try FileManager.default.createDirectory(at: libraryURL.appendingPathComponent("Metadata", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryURL.appendingPathComponent("Originals", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryURL.appendingPathComponent("Previews", isDirectory: true), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: libraryURL.appendingPathComponent("Diagnostics", isDirectory: true), withIntermediateDirectories: true)

        XCTAssertThrowsError(try DocumentLibraryService.validateLibrary(at: libraryURL))
    }

    func testPersistedLibraryURLRoundTripsNormalizedPath() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Remember Me")

        defer {
            DocumentLibraryService.persistLibraryURL(nil)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let createdLibraryURL = try DocumentLibraryService.createLibrary(at: libraryURL)

        DocumentLibraryService.persistLibraryURL(createdLibraryURL)

        XCTAssertEqual(
            DocumentLibraryService.restorePersistedLibraryURL(),
            createdLibraryURL.standardizedFileURL
        )
    }

    func testClearingPersistedLibraryURLRemovesStartupRestoreTarget() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryURL = tempRoot.appendingPathComponent("Forget Me")

        defer {
            DocumentLibraryService.persistLibraryURL(nil)
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let createdLibraryURL = try DocumentLibraryService.createLibrary(at: libraryURL)
        DocumentLibraryService.persistLibraryURL(createdLibraryURL)

        DocumentLibraryService.persistLibraryURL(nil)

        XCTAssertNil(DocumentLibraryService.restorePersistedLibraryURL())
    }

    @MainActor
    func testLibraryContainersStayIsolated() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let libraryAURL = tempRoot.appendingPathComponent("Library A")
        let libraryBURL = tempRoot.appendingPathComponent("Library B")

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let createdLibraryAURL = try DocumentLibraryService.createLibrary(at: libraryAURL)
        let createdLibraryBURL = try DocumentLibraryService.createLibrary(at: libraryBURL)

        let containerA = try DocumentLibraryService.openModelContainer(for: createdLibraryAURL)
        let contextA = containerA.mainContext
        contextA.insert(
            DocumentRecord(
                originalFileName: "invoice.pdf",
                title: "Invoice",
                importedAt: .now,
                pageCount: 1,
                fileSize: 4_096,
                contentHash: "seededhash",
                storedFilePath: "Originals/2026/03/test.pdf"
            )
        )
        try contextA.save()

        let containerB = try DocumentLibraryService.openModelContainer(for: createdLibraryBURL)
        let documentsInLibraryB = try containerB.mainContext.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertTrue(documentsInLibraryB.isEmpty)

        let reopenedContainerA = try DocumentLibraryService.openModelContainer(for: createdLibraryAURL)
        let documentsInLibraryA = try reopenedContainerA.mainContext.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documentsInLibraryA.count, 1)
        XCTAssertEqual(documentsInLibraryA.first?.title, "Invoice")
        XCTAssertTrue(FileManager.default.fileExists(atPath: DocumentLibraryService.metadataStoreURL(for: createdLibraryAURL).path))
    }

    @MainActor
    func testImportUseCaseCopiesPdfAndCreatesRecord() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcePDFURL = tempRoot.appendingPathComponent("invoice_march-2026.pdf")
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Import Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: sourcePDFURL))

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let importResult = ImportPDFDocumentsUseCase.execute(
            urls: [sourcePDFURL],
            into: libraryURL,
            using: context
        )

        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertFalse(importResult.hasFailures)

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.title, "Invoice March 2026")
        XCTAssertEqual(documents.first?.pageCount, 1)
        XCTAssertFalse(documents.first?.contentHash.isEmpty ?? true)
        XCTAssertGreaterThan(documents.first?.fileSize ?? 0, 0)
        XCTAssertNotNil(documents.first?.sourceCreatedAt)

        guard let storedFilePath = documents.first?.storedFilePath else {
            XCTFail("Expected imported document to include a stored file path")
            return
        }

        XCTAssertTrue(storedFilePath.hasPrefix("Originals/"))
        XCTAssertTrue(DocumentStorageService.fileExists(at: storedFilePath, libraryURL: libraryURL))
    }

    @MainActor
    func testImportUseCaseContinuesAfterPerFileFailure() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let missingPDFURL = tempRoot.appendingPathComponent("missing.pdf")
        let validPDFURL = tempRoot.appendingPathComponent("valid.pdf")
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Import Failure Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: validPDFURL))

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let importResult = ImportPDFDocumentsUseCase.execute(
            urls: [missingPDFURL, validPDFURL],
            into: libraryURL,
            using: context
        )

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertFalse(importResult.hasDuplicates)
        XCTAssertEqual(importResult.failures.count, 1)
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.originalFileName, "valid.pdf")
    }

    @MainActor
    func testImportUseCaseSkipsDuplicatePdfByHash() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let sourcePDFURL = tempRoot.appendingPathComponent("original.pdf")
        let duplicatePDFURL = tempRoot.appendingPathComponent("duplicate-copy.pdf")
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Import Duplicate Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: sourcePDFURL))
        try FileManager.default.copyItem(at: sourcePDFURL, to: duplicatePDFURL)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let firstImport = ImportPDFDocumentsUseCase.execute(
            urls: [sourcePDFURL],
            into: libraryURL,
            using: context
        )
        XCTAssertEqual(firstImport.importedCount, 1)

        let secondImport = ImportPDFDocumentsUseCase.execute(
            urls: [duplicatePDFURL],
            into: libraryURL,
            using: context
        )

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(secondImport.importedCount, 0)
        XCTAssertEqual(secondImport.duplicates.count, 1)
        XCTAssertFalse(secondImport.summaryMessage.isEmpty)
        XCTAssertEqual(documents.count, 1)
    }

    @MainActor
    func testImportUseCaseReportsUnsupportedFilesAndImportsValidPDFs() throws {
        let tempRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let validPDFURL = tempRoot.appendingPathComponent("invoice.pdf")
        let unsupportedTextURL = tempRoot.appendingPathComponent("notes.txt")
        let libraryURL = try DocumentLibraryService.createLibrary(
            at: tempRoot.appendingPathComponent("Mixed Import Library")
        )

        defer {
            try? FileManager.default.removeItem(at: tempRoot)
        }

        let pdfDocument = PDFDocument()
        pdfDocument.insert(PDFPage(), at: 0)
        XCTAssertTrue(pdfDocument.write(to: validPDFURL))
        try "hello".write(to: unsupportedTextURL, atomically: true, encoding: .utf8)

        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let importResult = ImportPDFDocumentsUseCase.execute(
            urls: [validPDFURL, unsupportedTextURL],
            into: libraryURL,
            using: context
        )

        let documents = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(importResult.importedCount, 1)
        XCTAssertEqual(importResult.unsupportedFiles.count, 1)
        XCTAssertEqual(importResult.unsupportedFiles.first?.fileName, "notes.txt")
        XCTAssertTrue(importResult.summaryMessage.contains("unsupported"))
        XCTAssertEqual(documents.count, 1)
    }

    @MainActor
    func testCreateAndAssignLabelCreatesSingleNormalizedLabel() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let document = DocumentRecord(
            originalFileName: "contract.pdf",
            title: "Contract",
            importedAt: .now,
            pageCount: 1
        )
        context.insert(document)

        let firstLabel = try ManageLabelsUseCase.createAndAssignLabel(named: "  Finance   Team  ", to: document, using: context)
        let secondLabel = try ManageLabelsUseCase.createAndAssignLabel(named: "finance team", to: document, using: context)

        let labels = try context.fetch(FetchDescriptor<LabelTag>())
        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(firstLabel.persistentModelID, secondLabel.persistentModelID)
        XCTAssertEqual(document.labels.count, 1)
        XCTAssertEqual(document.labels.first?.name, "Finance Team")
    }

    @MainActor
    func testRenameLabelMergesAssignmentsIntoExistingLabel() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let finance = LabelTag(name: "Finance")
        let archive = LabelTag(name: "Archive")
        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1, labels: [finance])
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1, labels: [archive])

        context.insert(finance)
        context.insert(archive)
        context.insert(documentA)
        context.insert(documentB)
        try context.save()

        let survivingLabel = try ManageLabelsUseCase.rename(archive, to: "Finance", using: context)
        let labels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(survivingLabel.name, "Finance")
        XCTAssertEqual(documentA.labels.first?.name, "Finance")
        XCTAssertEqual(documentB.labels.first?.name, "Finance")
    }

    @MainActor
    func testDeleteLabelRemovesAssignmentsButKeepsDocuments() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Receipts")
        let document = DocumentRecord(originalFileName: "receipt.pdf", title: "Receipt", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(document)
        try context.save()

        try ManageLabelsUseCase.delete(label, using: context)

        let remainingDocuments = try context.fetch(FetchDescriptor<DocumentRecord>())
        let remainingLabels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(remainingDocuments.count, 1)
        XCTAssertTrue(remainingDocuments[0].labels.isEmpty)
        XCTAssertTrue(remainingLabels.isEmpty)
    }

    @MainActor
    func testLabelFilterRequiresAllSelectedLabels() throws {
        let finance = LabelTag(name: "Finance")
        let archive = LabelTag(name: "Archive")
        let matchingDocument = DocumentRecord(originalFileName: "both.pdf", title: "Both", importedAt: .now, pageCount: 1, labels: [finance, archive])
        let partialDocument = DocumentRecord(originalFileName: "finance.pdf", title: "Finance Only", importedAt: .now, pageCount: 1, labels: [finance])

        let matchingIDs = Set([finance.persistentModelID, archive.persistentModelID])

        XCTAssertTrue(ManageLabelsUseCase.matchingAllSelectedLabels(matchingDocument, selectedLabelIDs: matchingIDs))
        XCTAssertFalse(ManageLabelsUseCase.matchingAllSelectedLabels(partialDocument, selectedLabelIDs: matchingIDs))
    }

    @MainActor
    func testAssignLabelToMultipleDocumentsAddsItToAllSelectedDocuments() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Travel")
        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1)
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(documentA)
        context.insert(documentB)
        try context.save()

        try ManageLabelsUseCase.assign(label, to: [documentA, documentB], using: context)

        XCTAssertEqual(documentA.labels.map(\.name), ["Travel"])
        XCTAssertEqual(documentB.labels.map(\.name), ["Travel"])
    }

    @MainActor
    func testRemoveLabelFromMultipleDocumentsRemovesItFromSelectionOnly() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let label = LabelTag(name: "Legal")
        let retainedLabel = LabelTag(name: "Archive")
        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1, labels: [label])
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1, labels: [label, retainedLabel])
        let documentC = DocumentRecord(originalFileName: "c.pdf", title: "C", importedAt: .now, pageCount: 1, labels: [label])
        context.insert(label)
        context.insert(retainedLabel)
        context.insert(documentA)
        context.insert(documentB)
        context.insert(documentC)
        try context.save()

        try ManageLabelsUseCase.remove(label, from: [documentA, documentB], using: context)

        XCTAssertTrue(documentA.labels.isEmpty)
        XCTAssertEqual(documentB.labels.map(\.name), ["Archive"])
        XCTAssertEqual(documentC.labels.map(\.name), ["Legal"])
    }

    @MainActor
    func testCreateAndAssignLabelToMultipleDocumentsCreatesOneSharedLabel() throws {
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)
        let context = container.mainContext

        let documentA = DocumentRecord(originalFileName: "a.pdf", title: "A", importedAt: .now, pageCount: 1)
        let documentB = DocumentRecord(originalFileName: "b.pdf", title: "B", importedAt: .now, pageCount: 1)
        context.insert(documentA)
        context.insert(documentB)
        try context.save()

        let label = try ManageLabelsUseCase.createAndAssignLabel(named: " Batch   Review ", to: [documentA, documentB], using: context)
        let labels = try context.fetch(FetchDescriptor<LabelTag>())

        XCTAssertEqual(labels.count, 1)
        XCTAssertEqual(label.name, "Batch Review")
        XCTAssertEqual(documentA.labels.map(\.name), ["Batch Review"])
        XCTAssertEqual(documentB.labels.map(\.name), ["Batch Review"])
    }
}