import XCTest
import PDFKit
import UIKit
@testable import PdfPipe

@MainActor
final class BasicTests: XCTestCase {
    func testFilenameJoinsKeepEarlierSeparatorsAndManualEditCanUndo() throws {
        var name = FilenameComposer()
        name.append(id: "date", value: "2026-10-05")
        name.append(id: "first", value: "Acme")
        name.separator = .underscore
        name.append(id: "second", value: "Invoice")
        XCTAssertEqual(try name.validFilename.get(), "2026-10-05-Acme_Invoice.pdf")
        name.toggle(id: "first", value: "Acme")
        XCTAssertEqual(try name.validFilename.get(), "2026-10-05_Invoice.pdf")
        name.editCompleteName("My document.pdf")
        XCTAssertEqual(try name.validFilename.get(), "My document.pdf")
        name.undoEdit()
        XCTAssertEqual(try name.validFilename.get(), "2026-10-05_Invoice.pdf")
        name.editCompleteName("")
        XCTAssertThrowsError(try name.validFilename.get())
    }

    func testAutomaticOCRKeepsEmbeddedTextAndSourceBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let source = root.appendingPathComponent("mixed.pdf")
        let image = UIGraphicsImageRenderer(size: CGSize(width: 700, height: 170)).image { context in
            UIColor.white.setFill()
            context.cgContext.fill(CGRect(x: 0, y: 0, width: 700, height: 170))
            ("ACME INVOICE" as NSString).draw(at: CGPoint(x: 30, y: 35),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 70), .foregroundColor: UIColor.black])
        }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: source) { context in
            context.beginPage()
            ("Invoice date: 2026-10-05" as NSString).draw(at: CGPoint(x: 45, y: 50),
                withAttributes: [.font: UIFont.systemFont(ofSize: 24)])
            image.draw(in: CGRect(x: 45, y: 250, width: 500, height: 120))
        }
        let original = try Data(contentsOf: source)
        let session = try TemporarySession(root: root)
        let engine = DocumentEngine(session: session)
        let imported = try await engine.prepare(staged: source, originalName: "mixed.pdf")
        let result = try await engine.processAutomatically(imported) { _ in }
        let extracted = try XCTUnwrap(PDFDocument(url: result.document.url)?.page(at: 0)?.string)
        XCTAssertTrue(extracted.contains("Invoice date: 2026-10-05"))
        let page = try XCTUnwrap(PDFDocument(url: result.document.url)?.page(at: 0))
        let selected = page.selection(for: page.bounds(for: .cropBox))?.string ?? ""
        XCTAssertTrue(selected.localizedCaseInsensitiveContains("ACME"),
            "OCR status: \(result.status); PDFKit page text: \(extracted); selection: \(selected)")
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
