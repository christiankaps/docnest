import SwiftUI
import PDFKit

struct PDFViewRepresentable: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            let targetURL = url
            Task.detached(priority: .userInitiated) {
                let document = PDFDocument(url: targetURL)
                await MainActor.run {
                    guard pdfView.window != nil else { return }
                    pdfView.document = document
                    pdfView.goToFirstPage(nil)
                }
            }
        }
    }
}