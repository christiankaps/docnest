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
            importedAt: .now,
            pageCount: 1,
            storedFilePath: "/tmp/test-path.pdf"
        )
        context.insert(doc)
        try context.save()

        let fetched = try context.fetch(FetchDescriptor<DocumentRecord>())
        XCTAssertEqual(fetched.first?.storedFilePath, "/tmp/test-path.pdf")
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
        XCTAssertEqual(importResult.failures.count, 1)
        XCTAssertEqual(documents.count, 1)
        XCTAssertEqual(documents.first?.originalFileName, "valid.pdf")
    }
}