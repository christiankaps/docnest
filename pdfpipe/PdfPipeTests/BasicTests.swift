import XCTest
import PDFKit
import UIKit
@testable import PdfPipe

@MainActor
final class BasicTests: XCTestCase {
    func testEarlyAndRepeatedWordsRemainVisibleInCrowdedDocuments() {
        let alphabet = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ")
        let bodyWords = (0..<35).map { "Fachwort\(alphabet[$0 / 26])\(alphabet[$0 % 26])" }
        let crowded = (["Absender", "Anschrift", "Kontakt", "Kundennummer", "Referenz", "Datum", "Betreff: Rechnung"]
            + bodyWords + bodyWords + bodyWords).joined(separator: "\n")
        XCTAssertTrue(DocumentAnalyzer.analyze(pages: [crowded]).words.contains { $0.id == "rechnung" })
        let splitSubject = (["Absender", "Anschrift", "Kontakt", "Kundennummer", "Referenz", "Datum", "Thema:", "Lieferumfang"]
            + bodyWords + bodyWords + bodyWords).joined(separator: "\n")
        XCTAssertTrue(DocumentAnalyzer.analyze(pages: [splitSubject]).words.contains { $0.id == "lieferumfang" })
        XCTAssertTrue(DocumentAnalyzer.analyze(pages: ["Wartungsplan\nInhalt", "Wartungsplan\nWeitere Details"])
            .words.contains { $0.id == "wartungsplan" })

        let opening = Array(repeating: "Filler", count: 12).joined(separator: "\n") + "\nEinleitung"
        let pages = [opening] + Array(repeating: "Zwischenseite", count: 4) + ["Anhang"]
        let pageScores = Dictionary(uniqueKeysWithValues: DocumentAnalyzer.analyze(pages: pages)
            .words.map { ($0.id, $0.score) })
        XCTAssertGreaterThan((pageScores["einleitung"] ?? 0) - (pageScores["anhang"] ?? 0), 0.8)
    }

    func testWordSuggestionsKeepDocumentTermsButFilterFiller() {
        let analysis = DocumentAnalyzer.analyze(pages: [
            "Invoice Rechnung Mahnung Bank Kundenservice Total Betrag IBAN Telefon Email Date Datum Number Nummer",
            "the und www"
        ])
        let suggestions = Set(analysis.words.map { $0.text.lowercased() })
        for term in ["invoice", "rechnung", "mahnung", "bank", "kundenservice", "total", "betrag",
                     "iban", "telefon", "email", "date", "datum", "number", "nummer"] {
            XCTAssertTrue(suggestions.contains(term), "Missing document term: \(term)")
        }
        for filler in ["the", "und", "www"] {
            XCTAssertFalse(suggestions.contains(filler), "Unexpected filler: \(filler)")
        }
    }

    func testWordRankingUsesCappedSizeAndStyleWithoutPromotingRepeatedHeaders() {
        func token(_ text: String, size: Double?, bold: Bool = false, italic: Bool = false) -> AnalysisToken {
            AnalysisToken(text: text, size: size, bold: bold, italic: italic, confidence: 1, source: .embedded)
        }
        func line(_ word: String, size: Double?, top: Double, bold: Bool = false, italic: Bool = false) -> AnalysisLine {
            AnalysisLine(text: word, tokens: [token(word, size: size, bold: bold, italic: italic)], topFraction: top)
        }
        let first = AnalysisPage(text: "", lines: [
            line("Giantlogo", size: 80, top: 0.02),
            line("Subject", size: 22, top: 0.12, bold: true),
            line("Ordinary", size: 11, top: 0.20),
            line("Details", size: 11, top: 0.25),
            line("Emphasis", size: 11, top: 0.50, italic: true),
            line("Baseline", size: 11, top: 0.55),
            line("Confidential", size: 11, top: 0.95)
        ])
        let second = AnalysisPage(text: "", lines: [
            line("Context", size: 11, top: 0.20),
            line("Another", size: 11, top: 0.25),
            line("Confidential", size: 11, top: 0.95)
        ])
        let ranked = DocumentAnalyzer.analyze(pages: [first, second]).words
        let scores = Dictionary(uniqueKeysWithValues: ranked.map { ($0.id, $0.score) })
        XCTAssertGreaterThan(scores["subject"] ?? 0, scores["giantlogo"] ?? 0)
        XCTAssertGreaterThan(scores["emphasis"] ?? 0, scores["baseline"] ?? 0)
        XCTAssertLessThan(scores["confidential"] ?? 0, scores["baseline"] ?? 0)
        XCTAssertEqual(DocumentAnalyzer.analyze(pages: ["Alpha Beta"]).words.map(\.text), ["Alpha", "Beta"])

        let neutralTerms = AnalysisPage(text: "", lines: [
            line("Invoice", size: nil, top: 0.10),
            line("Contract", size: nil, top: 0.12),
            line("Context", size: nil, top: 0.20),
            line("Details", size: nil, top: 0.25),
            line("Mahnung", size: nil, top: 0.60),
            line("Reminder", size: nil, top: 0.65)
        ])
        let neutralScores = Dictionary(uniqueKeysWithValues: DocumentAnalyzer.analyze(pages: [neutralTerms]).words.map { ($0.id, $0.score) })
        XCTAssertEqual(neutralScores["invoice"], neutralScores["contract"])
        XCTAssertEqual(neutralScores["mahnung"], neutralScores["reminder"])

        let native = AnalysisPage(text: "Invoice", lines: [line("Invoice", size: 10, top: 0.50)])
        let recognized = DocumentAnalyzer.ocrLine("Invoice", bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.05),
            pageHeight: 600, confidence: 0.9)
        let enriched = DocumentAnalyzer.mergingOCR([recognized], into: native)
        XCTAssertEqual(enriched.lines[0].tokens[0].size, 30)
        XCTAssertEqual(enriched.lines[0].tokens[0].source, .ocr)

        let fragmented = AnalysisPage(text: "Rech nung", lines: [
            AnalysisLine(text: "Rech nung", tokens: [token("Rech", size: 10), token("nung", size: 10)],
                topFraction: 0.15)
        ])
        let corrected = DocumentAnalyzer.ocrLine("Rechnung", bounds: CGRect(x: 0.1, y: 0.8, width: 0.3, height: 0.05),
            pageHeight: 600, confidence: 0.9)
        let merged = DocumentAnalyzer.mergingOCR([corrected], into: fragmented)
        XCTAssertTrue(DocumentAnalyzer.analyze(pages: [merged]).words.contains { $0.id == "rechnung" })
        XCTAssertEqual(enriched.lines.count, 1, "Matching OCR must not count an existing line twice")
    }

    func testNativePDFTextCarriesVisualSize() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".pdf")
        defer { try? FileManager.default.removeItem(at: url) }
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            ("Ordinary details" as NSString).draw(at: CGPoint(x: 40, y: 60),
                withAttributes: [.font: UIFont.systemFont(ofSize: 12)])
            ("Subject" as NSString).draw(at: CGPoint(x: 40, y: 150),
                withAttributes: [.font: UIFont.boldSystemFont(ofSize: 28)])
            ("Emphasis" as NSString).draw(at: CGPoint(x: 40, y: 240),
                withAttributes: [.font: UIFont.italicSystemFont(ofSize: 12)])
        }
        let page = try XCTUnwrap(PDFDocument(url: url)?.page(at: 0))
        let tokens = DocumentAnalyzer.extractPage(page).lines.flatMap(\.tokens)
        let ordinary = try XCTUnwrap(tokens.first { $0.text == "Ordinary" })
        let subject = try XCTUnwrap(tokens.first { $0.text == "Subject" })
        XCTAssertGreaterThan(subject.size ?? 0, ordinary.size ?? 0)
    }

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
        let suggestedWords = Set(result.analysis.words.map(\.id))
        XCTAssertTrue(suggestedWords.contains("acme"))
        XCTAssertTrue(suggestedWords.contains("invoice"))
        XCTAssertEqual(try Data(contentsOf: source), original)
    }
}
