import CoreGraphics
import Foundation
import OSLog
import PDFKit
import Vision

enum OCRTextExtractionService {
    private static let logger = Logger(subsystem: "com.kaps.docnest", category: "ocr")

    /// Rendering DPI for converting PDF pages to images for OCR.
    private static let renderDPI: CGFloat = 300.0

    /// Extracts text from a PDF, combining PDFKit fast path with Vision OCR fallback.
    /// Returns `nil` only when the document has zero pages.
    /// Returns an empty string when OCR produces no text (genuinely blank pages).
    static func extractText(from pdfDocument: PDFDocument) async -> String? {
        guard pdfDocument.pageCount > 0 else { return nil }

        var pageTexts: [String] = []

        for pageIndex in 0..<pdfDocument.pageCount {
            if Task.isCancelled { return nil }

            guard let page = pdfDocument.page(at: pageIndex) else { continue }

            // Fast path: use PDFKit embedded text
            if let pdfText = page.string, !pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                pageTexts.append(pdfText)
                continue
            }

            // Slow path: render page to image and run Vision OCR
            if let ocrText = await ocrPage(page, pageIndex: pageIndex) {
                pageTexts.append(ocrText)
            }
        }

        return pageTexts.isEmpty ? "" : pageTexts.joined(separator: "\n")
    }

    /// Runs Vision OCR on a single PDF page rendered as an image.
    private static func ocrPage(_ page: PDFPage, pageIndex: Int) async -> String? {
        guard let cgImage = renderPageToImage(page) else {
            logger.warning("Failed to render page \(pageIndex) to image for OCR")
            return nil
        }

        return await withCheckedContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error {
                    logger.error("OCR failed on page \(pageIndex): \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let observations = request.results as? [VNRecognizedTextObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                let lines = observations.compactMap { $0.topCandidates(1).first?.string }
                let text = lines.joined(separator: "\n")
                continuation.resume(returning: text.isEmpty ? nil : text)
            }

            request.recognitionLevel = .accurate
            request.usesLanguageCorrection = true

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                logger.error("Vision request handler failed on page \(pageIndex): \(error.localizedDescription)")
                continuation.resume(returning: nil)
            }
        }
    }

    /// Renders a PDF page to a CGImage at the configured DPI.
    private static func renderPageToImage(_ page: PDFPage) -> CGImage? {
        let mediaBox = page.bounds(for: .mediaBox)
        let scale = renderDPI / 72.0
        let width = Int(mediaBox.width * scale)
        let height = Int(mediaBox.height * scale)

        guard width > 0, height > 0 else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: 0,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        ) else { return nil }

        context.setFillColor(CGColor.white)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))

        context.scaleBy(x: scale, y: scale)
        page.draw(with: .mediaBox, to: context)

        return context.makeImage()
    }
}
