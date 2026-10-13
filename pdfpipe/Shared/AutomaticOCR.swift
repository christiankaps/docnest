import Foundation
import PDFKit
import Vision
import CoreText

struct OCRPayload {
    var url: URL
    var pages: [String]
    var status: String
}

private struct OCRLine {
    var text: String
    var bounds: CGRect
}

/// Recognition always runs. PDF re-emission happens only when missing text can be
/// added without discarding annotations or form/signature state.
enum AutomaticOCR {
    static func process(_ source: URL, to target: URL,
        progress: @Sendable (String) async -> Void) async throws -> OCRPayload {
        guard let pdf = PDFDocument(url: source), let cgPDF = CGPDFDocument(source as CFURL) else {
            throw PipeError.message("Cannot open the PDF for OCR.")
        }
        let deadline = Date().addingTimeInterval(120)
        var pages: [String] = []
        var missingByPage: [[OCRLine]] = []
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard Date() < deadline else { throw PipeError.message("OCR reached its two-minute limit.") }
            await progress("Recognizing page \(index + 1) of \(pdf.pageCount)…")
            guard let page = pdf.page(at: index), let cgPage = cgPDF.page(at: index + 1) else {
                throw PipeError.message("Cannot read a PDF page for OCR.")
            }
            let crop = cgPage.getBoxRect(.cropBox)
            let rotated = abs(cgPage.rotationAngle) % 180 == 90
            let width = rotated ? crop.height : crop.width
            let height = rotated ? crop.width : crop.height
            let scale = min(2.5, sqrt(4_000_000 / max(1, width * height)))
            let pixelWidth = max(1, Int(width * scale))
            let pixelHeight = max(1, Int(height * scale))
            let lines = try autoreleasepool { () throws -> [OCRLine] in
                guard let bitmap = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                    bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                    throw PipeError.message("Not enough memory to render this page.")
                }
                bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
                bitmap.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                bitmap.concatenate(cgPage.getDrawingTransform(.cropBox,
                    rect: CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight),
                    rotate: 0, preserveAspectRatio: true))
                bitmap.drawPDFPage(cgPage)
                guard let image = bitmap.makeImage() else {
                    throw PipeError.message("Cannot render the OCR page.")
                }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                try VNImageRequestHandler(cgImage: image).perform([request])
                return (request.results ?? []).compactMap { observation in
                    guard let text = observation.topCandidates(1).first?.string,
                          !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    return OCRLine(text: text, bounds: observation.boundingBox)
                }
            }
            try Task.checkCancellation()
            let embedded = page.string ?? ""
            let existingBounds = page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine()
                .map { $0.bounds(for: page) } ?? []
            let embeddedFolded = embedded.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
            let missing = lines.filter { line in
                let folded = line.text.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)
                if embeddedFolded.contains(folded) { return false }
                let observed = CGRect(x: crop.minX + line.bounds.minX * crop.width,
                    y: crop.minY + line.bounds.minY * crop.height,
                    width: line.bounds.width * crop.width, height: line.bounds.height * crop.height)
                return !existingBounds.contains { existing in
                    let overlap = existing.intersection(observed)
                    return !overlap.isNull && overlap.width * overlap.height > observed.width * observed.height * 0.35
                }
            }
            pages.append(embedded + "\n" + missing.map(\.text).joined(separator: "\n"))
            missingByPage.append(missing)
        }

        let added = missingByPage.reduce(0) { $0 + $1.count }
        guard added > 0 else {
            return OCRPayload(url: source, pages: pages, status: "OCR checked all \(pdf.pageCount) pages; embedded text kept")
        }
        let hasAnnotations = (0..<pdf.pageCount).contains { !(pdf.page(at: $0)?.annotations.isEmpty ?? true) }
        var form: CGPDFDictionaryRef?
        var permissions: CGPDFDictionaryRef?
        let catalog = cgPDF.catalog
        let hasFormOrSignature = catalog.map {
            CGPDFDictionaryGetDictionary($0, "AcroForm", &form) ||
                CGPDFDictionaryGetDictionary($0, "Perms", &permissions)
        } ?? false
        guard !hasAnnotations && !hasFormOrSignature else {
            return OCRPayload(url: source, pages: pages,
                status: "OCR found image text, but this PDF has annotations, forms, or signatures; the original PDF structure was kept")
        }

        await progress("Adding searchable text…")
        var initial = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(target as CFURL, mediaBox: &initial,
            [kCGPDFContextCreator: "PDF Pipe"] as CFDictionary) else {
            throw PipeError.message("Cannot create a searchable PDF.")
        }
        var completed = false
        defer { context.closePDF(); if !completed { try? FileManager.default.removeItem(at: target) } }
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard Date() < deadline, let page = cgPDF.page(at: index + 1) else {
                throw PipeError.message("OCR could not finish this document.")
            }
            let crop = page.getBoxRect(.cropBox)
            let rotated = abs(page.rotationAngle) % 180 == 90
            let box = CGRect(x: 0, y: 0, width: rotated ? crop.height : crop.width,
                height: rotated ? crop.width : crop.height)
            context.beginPDFPage([kCGPDFContextMediaBox: NSData(bytes: [box], length: MemoryLayout<CGRect>.size)] as CFDictionary)
            context.saveGState()
            context.concatenate(page.getDrawingTransform(.cropBox, rect: box, rotate: 0, preserveAspectRatio: true))
            context.drawPDFPage(page)
            context.restoreGState()
            for line in missingByPage[index] {
                let font = CTFontCreateWithName("Helvetica" as CFString, max(1, line.bounds.height * box.height), nil)
                let textLine = CTLineCreateWithAttributedString(NSAttributedString(string: line.text,
                    attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                let lineWidth = CGFloat(CTLineGetTypographicBounds(textLine, nil, nil, nil))
                guard lineWidth > 0 else { continue }
                context.saveGState()
                context.textMatrix = .identity
                context.translateBy(x: line.bounds.minX * box.width, y: line.bounds.minY * box.height)
                context.scaleBy(x: line.bounds.width * box.width / lineWidth, y: 1)
                context.setTextDrawingMode(.invisible)
                context.textPosition = .zero
                CTLineDraw(textLine, context)
                context.restoreGState()
            }
            context.endPDFPage()
        }
        completed = true
        let changedPages = missingByPage.filter { !$0.isEmpty }.count
        return OCRPayload(url: target, pages: pages,
            status: "OCR added searchable text to \(changedPages) \(changedPages == 1 ? "page" : "pages")")
    }
}
