import SwiftUI
import PDFKit
import OSLog

struct PDFViewRepresentable: NSViewRepresentable {
    let url: URL
    private static let performanceLogger = Logger(subsystem: "com.kaps.docnest", category: "performance")

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    func makeNSView(context: Context) -> PDFView {
        let pdfView = PDFView()
        pdfView.autoScales = true
        pdfView.displayMode = .singlePageContinuous
        return pdfView
    }

    func updateNSView(_ pdfView: PDFView, context: Context) {
        if pdfView.document?.documentURL != url {
            let requestID = context.coordinator.beginLoad(for: url)
            let targetURL = url
            Task.detached(priority: .userInitiated) {
                #if DEBUG
                let startTime = Date().timeIntervalSinceReferenceDate
                #endif
                let document = PDFDocument(url: targetURL)
                await MainActor.run {
                    guard context.coordinator.canApplyLoad(requestID, for: targetURL) else { return }
                    guard pdfView.window != nil else { return }
                    pdfView.document = document
                    pdfView.goToFirstPage(nil)
                    #if DEBUG
                    let elapsedMs = (Date().timeIntervalSinceReferenceDate - startTime) * 1000
                    Self.performanceLogger.log(
                        "[Performance][PDFLoad] path=\(targetURL.lastPathComponent, privacy: .public) duration=\(elapsedMs, format: .fixed(precision: 2))ms"
                    )
                    #endif
                }
            }
        }
    }

    final class Coordinator {
        private var activeRequestID = UUID()
        private var activeURL: URL?

        func beginLoad(for url: URL) -> UUID {
            let requestID = UUID()
            activeRequestID = requestID
            activeURL = url
            return requestID
        }

        func canApplyLoad(_ requestID: UUID, for url: URL) -> Bool {
            activeRequestID == requestID && activeURL == url
        }
    }
}
