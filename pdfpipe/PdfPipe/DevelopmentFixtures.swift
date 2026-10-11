#if DEBUG
import UIKit

/// Synthetic input used only by explicit UI test launches; never user's documents.
enum DevelopmentFixtures {
    static func document() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("PdfPipe-Test-Invoice.pdf")
        let renderer = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 612, height: 792))
        try renderer.writePDF(to: url) { context in
            context.beginPage()
            "INVOICE\nAcme Example\nInvoice number: INV-123\nTotal: 42.00".draw(in: CGRect(x: 50, y: 80, width: 510, height: 500),
                withAttributes: [.font: UIFont.systemFont(ofSize: 28)])
        }
        return url
    }
}
#endif
