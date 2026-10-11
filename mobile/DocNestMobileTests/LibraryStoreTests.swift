import PDFKit
import XCTest
@testable import DocNestMobile

@MainActor
final class LibraryStoreTests: XCTestCase {
    private var sandbox: URL!
    private var root: URL { sandbox.appending(path: "Library") }
    private var exports: URL { sandbox.appending(path: "Exports") }

    override func setUp() async throws {
        sandbox = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: sandbox, withIntermediateDirectories: true)
    }

    override func tearDown() async throws { try FileManager.default.removeItem(at: sandbox) }

    private func makeStore(checkpoint: @escaping LibraryStore.Checkpoint = { _ in }) -> LibraryStore {
        LibraryStore(root: root, exportRoot: exports, checkpoint: checkpoint)
    }

    private func source(_ text: String, name: String = "Invoice.pdf", pages: Int = 2) throws -> URL {
        let folder = sandbox.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appending(path: name)
        try DevelopmentFixtures.pdf(text: text, pages: pages).write(to: url)
        return url
    }

    func testImportRelaunchAndIndependentCopies() async throws {
        let store = makeStore()
        _ = try await store.load()
        let input = try source("Original ALPHA")
        let bytes = try Data(contentsOf: input)
        let date = Date(timeIntervalSince1970: 1_760_000_000)
        let result = try await store.importPDF(from: input, importedAt: date)
        XCTAssertFalse(result.isDuplicate)
        XCTAssertEqual(result.document.filename, "Invoice.pdf")
        XCTAssertEqual(result.document.title, "Invoice")
        XCTAssertEqual(result.document.pageCount, 2)
        XCTAssertEqual(result.document.reviewState, .inbox)
        XCTAssertEqual(result.document.processingState, .notStarted)
        XCTAssertEqual(result.document.dateSource, .importFallback)
        XCTAssertEqual(result.document.importedAt, date)
        let exported = try await store.exportCopy(for: result.document.id)
        XCTAssertEqual(exported.lastPathComponent, "Invoice.pdf")
        XCTAssertEqual(try Data(contentsOf: exported), bytes)
        try Data("Modified source".utf8).write(to: input)
        try Data("Modified export".utf8).write(to: exported)
        let original = try await store.originalURL(for: result.document.id)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded, [result.document])
        XCTAssertFalse(FileManager.default.fileExists(atPath: exported.path))
    }

    func testDuplicateBeforeCollisionAndPermanentNames() async throws {
        let store = makeStore()
        _ = try await store.load()
        let first = try source("First")
        let a = try await store.importPDF(from: first)
        let duplicate = try await store.importPDF(from: first, importedAt: .distantFuture)
        XCTAssertTrue(duplicate.isDuplicate)
        XCTAssertEqual(duplicate.document, a.document)
        let b = try await store.importPDF(from: source("Second"))
        let c = try await store.importPDF(from: source("Third", name: "invoice.PDF"))
        let d = try await store.importPDF(from: source("Fourth"))
        XCTAssertEqual(b.document.filename, "Invoice_2.pdf")
        XCTAssertEqual(c.document.filename, "invoice_3.PDF")
        XCTAssertEqual(d.document.filename, "Invoice_4.pdf")
        XCTAssertEqual(b.document.title, "Invoice_2")
        let loaded = try await makeStore().load()
        XCTAssertEqual(loaded.count, 4)
        XCTAssertEqual(loaded.first(where: { $0.id == a.document.id })?.filename, "Invoice.pdf")
        let export = try await store.exportCopy(for: c.document.id)
        XCTAssertEqual(export.lastPathComponent, "invoice_3.PDF")
    }

    func testRejectEncryptedIncludingEmptyPasswordAndMalformedInputs() async throws {
        let store = makeStore()
        _ = try await store.load()
        let good = try source("Keep me")
        let kept = try await store.importPDF(from: good)
        for password in ["secret", ""] {
            let encrypted = sandbox.appending(path: "Encrypted\(password).pdf")
            let pdf = try XCTUnwrap(PDFDocument(url: good))
            XCTAssertTrue(pdf.write(to: encrypted, withOptions: [.ownerPasswordOption: "owner", .userPasswordOption: password]))
            XCTAssertTrue(try XCTUnwrap(PDFDocument(url: encrypted)).isEncrypted)
            let original = try Data(contentsOf: encrypted)
            do { _ = try await store.importPDF(from: encrypted); XCTFail("Encrypted PDF accepted") }
            catch { XCTAssertEqual((error as? LibraryError), .encryptedPDF) }
            XCTAssertEqual(try Data(contentsOf: encrypted), original)
        }
        let corrupt = sandbox.appending(path: "Broken.pdf")
        try Data("%PDF-1.7\nnot a document".utf8).write(to: corrupt)
        do { _ = try await store.importPDF(from: corrupt); XCTFail("Corrupt PDF accepted") }
        catch { XCTAssertEqual((error as? LibraryError), .invalidPDF) }
        let reloaded = try await makeStore().load()
        XCTAssertEqual(reloaded, [kept.document])
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: root.appending(path: "Staging").path).isEmpty)
    }

    func testFailedWritesNeverPublishPartialDocuments() async throws {
        let goodStore = makeStore()
        _ = try await goodStore.load()
        let existing = try await goodStore.importPDF(from: source("Existing"))
        for phase in [LibraryStore.ImportPhase.copied, .validated, .metadataWritten] {
            let store = makeStore { current in
                if current == phase { throw CocoaError(.fileWriteOutOfSpace) }
            }
            _ = try await store.load()
            do { _ = try await store.importPDF(from: source("Failure")); XCTFail("Write should fail") }
            catch { XCTAssertEqual((error as NSError).code, CocoaError.fileWriteOutOfSpace.rawValue) }
            let reloaded = try await makeStore().load()
            XCTAssertEqual(reloaded, [existing.document])
        }
        let store = makeStore()
        _ = try await store.load()
        do { _ = try await store.importPDF(from: sandbox.appending(path: "Missing.pdf")); XCTFail("Missing source accepted") }
        catch { }
        let all = try await store.allDocuments()
        XCTAssertEqual(all, [existing.document])
    }

    func testImportCannotRetainASymbolicLinkToExternalContent() async throws {
        let store = makeStore()
        _ = try await store.load()
        let input = try source("External document")
        let originalBytes = try Data(contentsOf: input)
        let link = sandbox.appending(path: "Link.pdf")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: input)
        do { _ = try await store.importPDF(from: link); XCTFail("A symbolic link must not become a library original") }
        catch { XCTAssertEqual(error as? LibraryError, .invalidPDF) }
        let all = try await store.allDocuments()
        XCTAssertTrue(all.isEmpty)
        XCTAssertNotNil(PDFDocument(url: input))
        XCTAssertEqual(try Data(contentsOf: input), originalBytes)
    }

    func testStartupDiscardsOnlyUnpublishedTransactions() async throws {
        let store = makeStore()
        _ = try await store.load()
        let saved = try await store.importPDF(from: source("Committed before crash"))
        // Simulate process termination after metadata was written, before the commit rename.
        let abandoned = root.appending(path: "Staging/\(UUID().uuidString)")
        try FileManager.default.copyItem(at: root.appending(path: "Documents/\(saved.document.id.uuidString)"), to: abandoned)
        let recovered = try await makeStore().load()
        XCTAssertEqual(recovered, [saved.document])
        XCTAssertFalse(FileManager.default.fileExists(atPath: abandoned.path))
        // Published directory survives a crash before the UI acknowledges success; reimport is a duplicate.
        let relaunched = makeStore()
        _ = try await relaunched.load()
        let duplicate = try await relaunched.importPDF(from: await store.originalURL(for: saved.document.id))
        XCTAssertTrue(duplicate.isDuplicate)
    }

    func testDamagedOrFutureMetadataFailsClosedWithoutReset() async throws {
        let store = makeStore()
        _ = try await store.load()
        let saved = try await store.importPDF(from: source("Preserve on error"))
        let folder = root.appending(path: "Documents/\(saved.document.id.uuidString)")
        let metadata = folder.appending(path: "metadata.json")
        let originalMetadata = try Data(contentsOf: metadata)
        var json = try XCTUnwrap(JSONSerialization.jsonObject(with: originalMetadata) as? [String: Any])
        json["schemaVersion"] = 99
        try JSONSerialization.data(withJSONObject: json).write(to: metadata)
        do { _ = try await makeStore().load(); XCTFail("Unknown schema accepted") }
        catch { XCTAssertEqual(error as? LibraryError, .unsupportedVersion) }
        try Data("broken".utf8).write(to: metadata)
        do { _ = try await makeStore().load(); XCTFail("Corrupt metadata accepted") }
        catch { XCTAssertEqual(error as? LibraryError, .invalidLibrary) }
        XCTAssertTrue(FileManager.default.fileExists(atPath: folder.appending(path: "original.pdf").path))
        try originalMetadata.write(to: metadata)
        try FileManager.default.removeItem(at: folder.appending(path: "original.pdf"))
        do { _ = try await makeStore().load(); XCTFail("Missing original accepted") }
        catch { XCTAssertEqual(error as? LibraryError, .invalidLibrary) }
        XCTAssertEqual(try Data(contentsOf: metadata), originalMetadata)
    }

    func testSearchMapsExistingTextToPagesWithoutRewriting() async throws {
        let store = makeStore()
        _ = try await store.load()
        let input = try source("Needle ALPHA-123", pages: 3)
        let bytes = try Data(contentsOf: input)
        let saved = try await store.importPDF(from: input)
        let hits = try await store.search(document: saved.document.id, text: "alpha-123")
        XCTAssertEqual(hits.map(\.pageIndex), [0, 1, 2])
        let pdf = try XCTUnwrap(PDFDocument(data: bytes))
        for hit in hits {
            XCTAssertEqual(pdf.page(at: hit.pageIndex)?.selection(for: hit.range)?.string, "ALPHA-123")
            XCTAssertTrue(hit.snippet.contains("ALPHA-123"))
        }
        let original = try await store.originalURL(for: saved.document.id)
        XCTAssertEqual(try Data(contentsOf: original), bytes)
    }

    func testCalendarDatePrivacyConfigurationAndExportFailure() async throws {
        let calendar = Calendar(identifier: .gregorian)
        let date = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 12, day: 31)))
        let documentDate = DocumentDate(date, calendar: calendar)
        XCTAssertEqual(documentDate.year, 2026)
        XCTAssertEqual(try JSONDecoder().decode(DocumentDate.self, from: JSONEncoder().encode(documentDate)), documentDate)
        XCTAssertTrue(documentDate.isValid)
        XCTAssertTrue(LibraryStore.defaultRoot.path.contains("Library/Application Support"))
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "UIFileSharingEnabled") as? Bool, false)
        XCTAssertEqual(Bundle.main.object(forInfoDictionaryKey: "LSSupportsOpeningDocumentsInPlace") as? Bool, false)
        let store = makeStore()
        _ = try await store.load()
        let saved = try await store.importPDF(from: source("Export failure"))
        try Data("Block export directory".utf8).write(to: exports)
        do { _ = try await store.exportCopy(for: saved.document.id); XCTFail("Blocked export succeeded") }
        catch { }
        let original = try await store.originalURL(for: saved.document.id)
        XCTAssertNotNil(PDFDocument(url: original))
    }

    func testResourceCorpusBaseline() async throws {
        let store = makeStore()
        _ = try await store.load()
        // 250 text PDFs (1/2/10 pages) and 50 raster-heavy PDFs (1/5/20 pages).
        let width = 768, height = 1024
        var generator: UInt64 = 42
        let pixels = (0..<(width * height * 4)).map { index -> UInt8 in
            if index % 4 == 3 { return 255 }
            generator = generator &* 6364136223846793005 &+ 1
            return UInt8(truncatingIfNeeded: generator >> 32)
        }
        let provider = try XCTUnwrap(CGDataProvider(data: Data(pixels) as CFData))
        let cgImage = try XCTUnwrap(CGImage(width: width, height: height, bitsPerComponent: 8, bitsPerPixel: 32, bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.premultipliedLast.rawValue), provider: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent))
        let image = UIImage(cgImage: cgImage)
        let input = sandbox.appending(path: "Corpus.pdf")
        let start = Date()
        for index in 0..<300 {
            let scanned = index >= 250
            let pages = scanned ? [1, 5, 20][index % 3] : [1, 2, 10][index % 3]
            let data = autoreleasepool { DevelopmentFixtures.pdf(text: "Synthetic corpus \(index)", pages: pages, image: scanned ? image : nil) }
            try data.write(to: input)
            _ = try await store.importPDF(from: input)
        }
        let importTime = Date().timeIntervalSince(start)
        let loadStart = Date()
        let reloaded = makeStore()
        let all = try await reloaded.load()
        let loadTime = Date().timeIntervalSince(loadStart)
        XCTAssertEqual(all.count, 300)
        let largest = try XCTUnwrap(all.max(by: { $0.byteCount < $1.byteCount }))
        let url = try await reloaded.originalURL(for: largest.id)
        let openStart = Date()
        let pdf = try XCTUnwrap(PDFDocument(url: url))
        _ = pdf.page(at: 0)?.thumbnail(of: CGSize(width: 390, height: 550), for: .mediaBox)
        let openTime = Date().timeIntervalSince(openStart)
        let report = "Corpus: 300 PDFs, pages 1–20, bytes \(all.map(\.byteCount).min()!)–\(all.map(\.byteCount).max()!), total \(all.map(\.byteCount).reduce(0,+)); generation+import \(importTime)s; reload \(loadTime)s; largest open+first-page render \(openTime)s"
        print(report)
        let attachment = XCTAttachment(string: report)
        attachment.lifetime = .keepAlways
        add(attachment)
        // Generous regression ceilings, not a physical-device product promise.
        XCTAssertLessThan(loadTime, 10)
        XCTAssertLessThan(openTime, 10)
    }
}
