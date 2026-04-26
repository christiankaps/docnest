import SwiftUI
import PDFKit
import OSLog

struct PDFViewRepresentable: NSViewRepresentable {
    let url: URL
    @Binding var isReady: Bool
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
        let coordinator = context.coordinator
        let readiness = $isReady
        if pdfView.document?.documentURL == url {
            setReadiness(true, binding: readiness)
            return
        }
        guard !coordinator.isLoading(url) else { return }

        let requestID = coordinator.beginLoad(for: url)
        let targetURL = url
        setReadiness(false, binding: readiness)
        coordinator.installLoadTask(
            Task.detached(priority: .userInitiated) { [weak coordinator, weak pdfView] in
                #if DEBUG
                let startTime = Date().timeIntervalSinceReferenceDate
                #endif
                guard !Task.isCancelled else { return }
                let document = PDFDocument(url: targetURL)
                guard !Task.isCancelled else { return }

                await MainActor.run { [weak coordinator, weak pdfView] in
                    guard let coordinator else { return }
                    defer { coordinator.finishLoad(requestID) }
                    guard coordinator.canApplyLoad(requestID, for: targetURL) else { return }
                    guard let pdfView else { return }
                    pdfView.document = document
                    if document != nil {
                        Self.alignFirstPageTop(in: pdfView)
                        readiness.wrappedValue = true
                    } else {
                        readiness.wrappedValue = false
                    }
                    #if DEBUG
                    let elapsedMs = (Date().timeIntervalSinceReferenceDate - startTime) * 1000
                    Self.performanceLogger.log(
                        "[Performance][PDFLoad] path=\(targetURL.lastPathComponent, privacy: .public) duration=\(elapsedMs, format: .fixed(precision: 2))ms"
                    )
                    #endif
                }
            }
        )
    }

    static func dismantleNSView(_ nsView: PDFView, coordinator: Coordinator) {
        coordinator.cancelLoad(resetRequest: true)
        nsView.document = nil
    }

    static func firstPageTopDestinationPoint(for page: PDFPage, displayBox: PDFDisplayBox) -> NSPoint {
        let bounds = page.bounds(for: displayBox)
        return NSPoint(x: bounds.minX, y: bounds.maxY)
    }

    @MainActor
    static func alignFirstPageTop(in pdfView: PDFView) {
        guard let firstPage = pdfView.document?.page(at: 0) else { return }
        pdfView.autoScales = true
        pdfView.layoutDocumentView()
        pdfView.go(to: PDFDestination(
            page: firstPage,
            at: firstPageTopDestinationPoint(for: firstPage, displayBox: pdfView.displayBox)
        ))
    }

    @MainActor
    final class Coordinator {
        private var activeRequestID = UUID()
        private var activeURL: URL?
        private var loadTask: Task<Void, Never>?

        deinit {
            loadTask?.cancel()
        }

        func beginLoad(for url: URL) -> UUID {
            cancelLoad()
            let requestID = UUID()
            activeRequestID = requestID
            activeURL = url
            return requestID
        }

        func installLoadTask(_ task: Task<Void, Never>) {
            loadTask = task
        }

        func canApplyLoad(_ requestID: UUID, for url: URL) -> Bool {
            activeRequestID == requestID && activeURL == url
        }

        func isLoading(_ url: URL) -> Bool {
            activeURL == url && loadTask != nil
        }

        func finishLoad(_ requestID: UUID) {
            guard activeRequestID == requestID else { return }
            loadTask = nil
        }

        func cancelLoad(resetRequest: Bool = false) {
            loadTask?.cancel()
            loadTask = nil
            if resetRequest {
                activeURL = nil
                activeRequestID = UUID()
            }
        }
    }

    private func setReadiness(_ value: Bool, binding: Binding<Bool>) {
        Task { @MainActor in
            guard binding.wrappedValue != value else { return }
            binding.wrappedValue = value
        }
    }
}
