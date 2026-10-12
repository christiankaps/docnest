import XCTest
@testable import PdfPipe

final class DocumentAnalysisTests: XCTestCase {
    func testDocumentDatePrefersIssueDateOverDueDate() {
        let analysis = DocumentAnalyzer.analyze(pages: ["Invoice date: 2026-10-05\nDue date: 2026-11-05\nTelekom Rechnung Internet"])
        XCTAssertEqual(analysis.date, .found("2026-10-05"))
    }

    func testNoValidDateFallsBackButCompetingDatesStayAmbiguous() {
        XCTAssertEqual(DocumentAnalyzer.analyze(pages: ["Invoice 31.02.2026 with no valid date"]).date, .fallback)
        XCTAssertEqual(DocumentAnalyzer.analyze(pages: ["Invoice date: 2026-10-05\nInvoice date: 2026-10-06"]).date,
                       .ambiguous(["2026-10-05", "2026-10-06"]))
        XCTAssertEqual(DocumentAnalyzer.analyze(pages: ["Invoice date: 05/10/2026"]).date,
                       .ambiguous(["2026-05-10", "2026-10-05"]))
        XCTAssertEqual(DocumentAnalyzer.analyze(pages: ["Rechnungsdatum: 05.10.2026"]).date, .found("2026-10-05"))
    }

    func testRankingUsesHeadingAndIgnoresRepeatedFooter() {
        let analysis = DocumentAnalyzer.analyze(pages: [
            "Telekom Internet\nRechnung für Oktober\nKundendienst Kundendienst Kundendienst\nFooter repeated",
            "Internet Vertrag\nFooter repeated"
        ])
        XCTAssertTrue(analysis.hasText)
        XCTAssertEqual(analysis.words.first?.text, "Internet")
        XCTAssertFalse(analysis.words.map(\.text).contains("Footer"))
        XCTAssertFalse(analysis.words.map(\.text).contains("und"))
        XCTAssertEqual(DocumentAnalyzer.analyze(pages: [" \n "]).words, [])
    }
}
