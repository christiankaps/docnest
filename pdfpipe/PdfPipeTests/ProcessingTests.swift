import XCTest
import UIKit
import PDFKit
@testable import PdfPipe

@MainActor
final class ProcessingTests: XCTestCase {
    private var root: URL!
    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try FileManager.default.removeItem(at: root) }

    private func sourcePDF(text: String = "Original invoice", rotation: Int = 0, scanned: Bool = false) throws -> URL {
        let rect = CGRect(x: 0, y: 0, width: 612, height: 792)
        let url = root.appendingPathComponent("original.pdf")
        let image = UIGraphicsImageRenderer(size: rect.size).image { context in
            UIColor.white.setFill(); context.fill(rect)
            text.draw(at: CGPoint(x: 65, y: 150), withAttributes: [.font: UIFont.systemFont(ofSize: 38), .foregroundColor: UIColor.black])
        }
        try UIGraphicsPDFRenderer(bounds: rect).writePDF(to: url) { context in
            context.beginPage()
            if scanned { image.draw(in: rect) }
            else { text.draw(at: CGPoint(x: 65, y: 150), withAttributes: [.font: UIFont.systemFont(ofSize: 38)]) }
        }
        if rotation != 0 {
            let pdf = try XCTUnwrap(PDFDocument(url: url))
            pdf.page(at: 0)?.rotation = rotation
            XCTAssertTrue(pdf.write(to: url))
        }
        return url
    }

    private func prepared(_ source: URL) async throws -> (TemporarySession, DocumentEngine, ProcessedDocument) {
        let session = try TemporarySession(root: root.appendingPathComponent("sessions"))
        let engine = DocumentEngine(session: session)
        let staged = try DocumentEngine.stage(source, to: session.directory)
        let document = try await engine.prepare(staged: staged, originalName: source.lastPathComponent)
        return (session, engine, document)
    }

    func testRenamePreservesSourceAndPDFBytes() async throws {
        let source = try sourcePDF()
        let original = try Data(contentsOf: source)
        let (session, engine, _) = try await prepared(source)
        let pipeline = Pipeline(name: "Rename", steps: [.init(kind: .rename, template: "Invoice_{original}")])
        let result = try await engine.process(pipeline, text: "") { _ in }
        XCTAssertEqual(result.facts.filename, "Invoice_original.pdf")
        XCTAssertEqual(try Data(contentsOf: result.url), original)
        XCTAssertEqual(try Data(contentsOf: source), original)
        try session.cleanup()
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.directory.path))
    }

    func testOCRCreatesSearchableInvisibleTextAndPreservesAppearance() async throws {
        let source = try sourcePDF(text: "INVOICE ACME 12345", scanned: true)
        let original = try Data(contentsOf: source)
        let (session, engine, input) = try await prepared(source)
        XCTAssertFalse(input.facts.hasText)
        let result = try await engine.process(Pipeline(steps: [.init(kind: .ocr)]), text: "") { _ in }
        let pdf = try XCTUnwrap(PDFDocument(url: result.url))
        XCTAssertTrue(pdf.string?.contains("ACME") == true, pdf.string ?? "No exported text")
        XCTAssertNotNil(pdf.findString("ACME", withOptions: .caseInsensitive).first)
        let before = try raster(source), after = try raster(result.url)
        XCTAssertEqual(before.count, after.count)
        let differences = zip(before, after).filter { abs(Int($0) - Int($1)) > 5 }.count
        XCTAssertLessThan(Double(differences) / Double(before.count), 0.005, "Invisible OCR must not visibly change the document")
        XCTAssertEqual(try Data(contentsOf: source), original)
        try session.cleanup()
    }

    func testOCRKeepsExistingTextWithoutDuplication() async throws {
        let source = try sourcePDF(text: "Already searchable")
        let (session, engine, _) = try await prepared(source)
        let result = try await engine.process(Pipeline(steps: [.init(kind: .ocr)]), text: "") { _ in }
        let pdf = try XCTUnwrap(PDFDocument(url: result.url))
        XCTAssertEqual(pdf.findString("Already searchable", withOptions: []).count, 1)
        XCTAssertEqual(result.report, ["OCR processed 0 pages; existing text pages kept"])
        try session.cleanup()
    }

    func testForcedOCRReplacesExistingTextWithoutDuplicatingIt() async throws {
        let source = try sourcePDF(text: "INVOICE ACME 12345")
        let original = try Data(contentsOf: source)
        let (session, engine, _) = try await prepared(source)
        let result = try await engine.process(Pipeline(steps: [.init(kind: .ocr, skipExistingText: false)]), text: "") { _ in }
        let pdf = try XCTUnwrap(PDFDocument(url: result.url))
        XCTAssertEqual(pdf.findString("ACME", withOptions: .caseInsensitive).count, 1)
        XCTAssertEqual(result.report, ["OCR processed 1 pages; all pages recognized"])
        let before = try raster(source), after = try raster(result.url)
        XCTAssertEqual(before.count, after.count)
        let differences = zip(before, after).filter { abs(Int($0) - Int($1)) > 5 }.count
        XCTAssertLessThan(Double(differences) / Double(before.count), 0.01)
        XCTAssertEqual(try Data(contentsOf: source), original)
        try session.cleanup()
    }

    func testSkipExistingTextStillRecognizesScannedPagesInMixedPDF() async throws {
        let textSource = try sourcePDF(text: "EXISTING TEXT")
        let pdf = try XCTUnwrap(PDFDocument(data: Data(contentsOf: textSource)))
        let scannedSource = try sourcePDF(text: "SCANNED ACME", scanned: true)
        let scanned = try XCTUnwrap(PDFDocument(url: scannedSource))
        pdf.insert(try XCTUnwrap(scanned.page(at: 0)), at: 1)
        let source = root.appendingPathComponent("mixed.pdf")
        XCTAssertTrue(pdf.write(to: source))
        let original = try Data(contentsOf: source)
        let (session, engine, _) = try await prepared(source)
        let result = try await engine.process(Pipeline(steps: [.init(kind: .ocr)]), text: "") { _ in }
        let output = try XCTUnwrap(PDFDocument(url: result.url))
        XCTAssertEqual(output.findString("EXISTING TEXT", withOptions: []).count, 1)
        XCTAssertTrue(output.page(at: 1)?.string?.contains("ACME") == true)
        XCTAssertEqual(result.report, ["OCR processed 1 pages; existing text pages kept"])
        XCTAssertEqual(try Data(contentsOf: source), original)
        try session.cleanup()
    }

    func testRotatedScannedPageRemainsSearchable() async throws {
        let source = try sourcePDF(text: "ROTATED ACME INVOICE", rotation: 90, scanned: true)
        let (session, engine, _) = try await prepared(source)
        let result = try await engine.process(Pipeline(steps: [.init(kind: .ocr)]), text: "") { _ in }
        let pdf = try XCTUnwrap(PDFDocument(url: result.url))
        XCTAssertTrue(pdf.string?.contains("ACME") == true, pdf.string ?? "No text")
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).width, 792)
        XCTAssertEqual(pdf.page(at: 0)?.bounds(for: .mediaBox).height, 612)
        XCTAssertEqual(try raster(source), try raster(result.url))
        try session.cleanup()
    }

    func testImageConversionAndSourcePreservation() async throws {
        let rect = CGRect(x: 0, y: 0, width: 800, height: 600)
        let image = UIGraphicsImageRenderer(size: rect.size).image { context in UIColor.red.setFill(); context.fill(rect) }
        let source = root.appendingPathComponent("photo.png")
        let bytes = try XCTUnwrap(image.pngData()); try bytes.write(to: source)
        let (session, _, result) = try await prepared(source)
        XCTAssertEqual(result.facts.sourceFormat, "PNG")
        XCTAssertEqual(result.facts.pages, 1)
        XCTAssertNotNil(PDFDocument(url: result.url))
        XCTAssertEqual(try Data(contentsOf: source), bytes)
        try session.cleanup()
    }

    func testUnsupportedFileFailsWithoutChangingSource() async throws {
        let source = root.appendingPathComponent("unsupported.txt")
        let original = Data("not a PDF".utf8); try original.write(to: source)
        let session = try TemporarySession(root: root.appendingPathComponent("sessions"))
        let engine = DocumentEngine(session: session)
        let staged = try DocumentEngine.stage(source, to: session.directory)
        do { _ = try await engine.prepare(staged: staged, originalName: source.lastPathComponent); XCTFail("Must reject") }
        catch { XCTAssertTrue(error.localizedDescription.contains("Supported files")) }
        XCTAssertEqual(try Data(contentsOf: source), original)
        try session.cleanup()
    }

    func testOversizedFileIsRejectedBeforeCopying() throws {
        let source = root.appendingPathComponent("huge.pdf")
        FileManager.default.createFile(atPath: source.path, contents: nil)
        let handle = try FileHandle(forWritingTo: source)
        try handle.truncate(atOffset: UInt64(DocumentEngine.maximumBytes + 1)); try handle.close()
        let session = try TemporarySession(root: root.appendingPathComponent("sessions"))
        XCTAssertThrowsError(try DocumentEngine.stage(source, to: session.directory))
        XCTAssertFalse(FileManager.default.fileExists(atPath: session.directory.appendingPathComponent("incoming.pdf").path))
        try session.cleanup()
    }

    func testOCRRejectsAnnotationsWithoutChangingSource() async throws {
        let source = try sourcePDF()
        let pdf = try XCTUnwrap(PDFDocument(url: source))
        pdf.page(at: 0)?.addAnnotation(PDFAnnotation(bounds: CGRect(x: 10, y: 10, width: 50, height: 50), forType: .text, withProperties: nil))
        XCTAssertTrue(pdf.write(to: source))
        let original = try Data(contentsOf: source)
        let (session, engine, _) = try await prepared(source)
        do { _ = try await engine.process(Pipeline(steps: [.init(kind: .ocr)]), text: "") { _ in }; XCTFail("Must reject") }
        catch { XCTAssertTrue(error.localizedDescription.contains("annotated")) }
        XCTAssertEqual(try Data(contentsOf: source), original)
        try session.cleanup()
    }

    func testCancellationLeavesSourceAndNoSuccessfulResult() async throws {
        let source = try sourcePDF(scanned: true)
        let original = try Data(contentsOf: source)
        let (session, engine, _) = try await prepared(source)
        let task = Task {
            try await engine.process(Pipeline(steps: [.init(kind: .ocr)]), text: "") { _ in
                try? await Task.sleep(for: .seconds(1))
            }
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Expected cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: source), original)
        try session.cleanup()
    }

    private func raster(_ url: URL) throws -> Data {
        let document = try XCTUnwrap(CGPDFDocument(url as CFURL))
        let page = try XCTUnwrap(document.page(at: 1))
        let crop = page.getBoxRect(.cropBox)
        let rotated = abs(page.rotationAngle) % 180 == 90
        let width = Int(rotated ? crop.height : crop.width), height = Int(rotated ? crop.width : crop.height)
        let context = try XCTUnwrap(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
            bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 1, alpha: 1)); context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.concatenate(page.getDrawingTransform(.cropBox, rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
        context.drawPDFPage(page)
        return Data(bytes: try XCTUnwrap(context.data), count: width * height * 4)
    }
}
