import Foundation
import PDFKit
import Vision
import CoreText
import ImageIO
import UniformTypeIdentifiers

struct OCRPayload {
    var url: URL
    var preferredPages: [AnalysisPage]
    var status: String
}

private struct OCRLine {
    var text: String
    var bounds: CGRect
    var confidence: Float
}

/// Recognition always runs. Confident scan pages replace their old invisible
/// text layer in the temporary copy; native and ambiguous pages keep PDF text.
enum AutomaticOCR {
    static func rasterTransform(for page: CGPDFPage, pixelWidth: Int, pixelHeight: Int,
                                scale: CGFloat) -> CGAffineTransform {
        // Core Graphics fits small pages inside a larger rect without enlarging them.
        // Fit at page size first, then apply the requested raster scale explicitly.
        let fit = page.getDrawingTransform(.cropBox,
            rect: CGRect(x: 0, y: 0, width: CGFloat(pixelWidth) / scale,
                height: CGFloat(pixelHeight) / scale),
            rotate: 0, preserveAspectRatio: true)
        return fit.concatenating(CGAffineTransform(scaleX: scale, y: scale))
    }

    static func prioritizedLanguages(_ supported: [String], preferred: String) -> [String] {
        func normalized(_ identifier: String) -> String {
            identifier.replacingOccurrences(of: "_", with: "-").lowercased()
        }
        func compatible(_ candidate: String, with target: String) -> Bool {
            let candidate = Locale.Language(identifier: candidate)
            let target = Locale.Language(identifier: target)
            guard let languageCode = target.languageCode else { return false }
            return candidate.languageCode == languageCode && candidate.script == target.script
        }
        var remaining = supported
        var ordered: [String] = []
        for target in [preferred, "en-US"] {
            let targetCode = Locale.Language(identifier: target).languageCode
            if let targetCode, ordered.contains(where: {
                Locale.Language(identifier: $0).languageCode == targetCode
            }) {
                continue
            }
            let match = remaining.firstIndex { normalized($0) == normalized(target) }
                ?? remaining.firstIndex { compatible($0, with: target) }
            if let match {
                ordered.append(remaining.remove(at: match))
            }
        }
        return ordered
    }

    static func process(_ source: URL, to target: URL,
        progress: @Sendable (String, Double?) async -> Void) async throws -> OCRPayload {
        guard let pdf = PDFDocument(url: source), let cgPDF = CGPDFDocument(source as CFURL) else {
            throw PipeError.message("Cannot open the PDF for OCR.")
        }
        let deadline = Date().addingTimeInterval(120)
        let languageProbe = VNRecognizeTextRequest()
        languageProbe.recognitionLevel = .accurate
        languageProbe.automaticallyDetectsLanguage = true
        let supportedLanguages = (try? languageProbe.supportedRecognitionLanguages()) ?? []
        let recognitionLanguages = prioritizedLanguages(supportedLanguages,
            preferred: Locale.preferredLanguages.first ?? "en-US")
        var preferredPages: [AnalysisPage] = []
        var missingByPage: [[OCRLine]] = []
        var recognizedLinesByPage: [[OCRLine]] = []
        var replaceByPage: [Bool] = []
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard Date() < deadline else { throw PipeError.message("OCR reached its two-minute limit.") }
            await progress("Recognizing page \(index + 1) of \(pdf.pageCount)…",
                0.9 * Double(index) / Double(pdf.pageCount))
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
            let rasterTransform = Self.rasterTransform(for: cgPage, pixelWidth: pixelWidth,
                pixelHeight: pixelHeight, scale: scale)
            let lines = try autoreleasepool { () throws -> [OCRLine] in
                guard let bitmap = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
                    bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                    throw PipeError.message("Not enough memory to render this page.")
                }
                bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
                bitmap.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
                bitmap.concatenate(rasterTransform)
                bitmap.drawPDFPage(cgPage)
                guard let image = bitmap.makeImage() else {
                    throw PipeError.message("Cannot render the OCR page.")
                }
                let request = VNRecognizeTextRequest()
                request.recognitionLevel = .accurate
                request.usesLanguageCorrection = true
                request.automaticallyDetectsLanguage = true
                if !recognitionLanguages.isEmpty {
                    request.recognitionLanguages = recognitionLanguages
                }
                try VNImageRequestHandler(cgImage: image).perform([request])
                return (request.results ?? []).compactMap { observation in
                    guard let candidate = observation.topCandidates(1).first else { return nil }
                    let text = candidate.string
                    guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
                    return OCRLine(text: text, bounds: observation.boundingBox, confidence: candidate.confidence)
                }.sorted { left, right in
                    if abs(left.bounds.midY - right.bounds.midY) > 0.02 {
                        return left.bounds.midY > right.bounds.midY
                    }
                    return left.bounds.minX < right.bounds.minX
                }
            }
            try Task.checkCancellation()
            let embedded = page.string ?? ""
            let existingBounds = page.selection(for: page.bounds(for: .cropBox))?.selectionsByLine()
                .map { $0.bounds(for: page).applying(rasterTransform) } ?? []
            let missing = lines.filter { line in
                let observed = CGRect(x: line.bounds.minX * CGFloat(pixelWidth),
                    y: line.bounds.minY * CGFloat(pixelHeight),
                    width: line.bounds.width * CGFloat(pixelWidth),
                    height: line.bounds.height * CGFloat(pixelHeight))
                return !existingBounds.contains { existing in
                    let overlap = existing.intersection(observed)
                    return !overlap.isNull && overlap.width * overlap.height > observed.width * observed.height * 0.35
                }
            }
            let observed = lines.map {
                DocumentAnalyzer.ocrLine($0.text, bounds: $0.bounds, pageHeight: height,
                    confidence: $0.confidence)
            }
            let recognizedPageText = lines.map(\.text).joined(separator: "\n")
            let embeddedPage = DocumentAnalyzer.extractPage(page)
            let recognizedPage = AnalysisPage(text: recognizedPageText, lines: observed)
            let replace = !embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
                !lines.isEmpty && PDFPageOrigin.hasReplaceableOCR(on: cgPage)
            let missingObserved = missing.map {
                DocumentAnalyzer.ocrLine($0.text, bounds: $0.bounds, pageHeight: height,
                    confidence: $0.confidence)
            }
            let preferred: AnalysisPage
            let preferredPageText: String
            if replace || embedded.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                preferred = recognizedPage
                preferredPageText = recognizedPageText
            } else {
                preferredPageText = ([embedded] + missing.map(\.text)).joined(separator: "\n")
                preferred = AnalysisPage(text: preferredPageText,
                    lines: embeddedPage.lines + missingObserved)
            }
            preferredPages.append(preferred)
            missingByPage.append(missing)
            recognizedLinesByPage.append(lines)
            replaceByPage.append(replace)
            await progress("Recognized \(index + 1) of \(pdf.pageCount) pages",
                0.9 * Double(index + 1) / Double(pdf.pageCount))
        }

        await progress("Preparing suggestions…", 0.9)
        let replacements = replaceByPage.filter { $0 }.count
        let additions = missingByPage.enumerated().filter { !replaceByPage[$0.offset] && !$0.element.isEmpty }.count
        guard replacements > 0 || additions > 0 else {
            return OCRPayload(url: source, preferredPages: preferredPages,
                status: "OCR checked all \(pdf.pageCount) pages; native or uncertain PDF text kept")
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
            return OCRPayload(url: source, preferredPages: preferredPages,
                status: "Apple OCR was used for suggestions, but this PDF has annotations, forms, or signatures; its original text layer was kept")
        }

        await progress("Updating searchable text…", 0.9)
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
            if replaceByPage[index] {
                // Drawing the PDF page would carry its old OCR operators into the
                // result. A confident scan is already raster content, so render
                // its visible appearance and add only Apple's searchable text.
                let image = try Self.renderPage(page, maxPixels: 9_000_000, maxScale: 4)
                context.draw(image, in: box)
            } else {
                context.saveGState()
                context.concatenate(page.getDrawingTransform(.cropBox, rect: box,
                    rotate: 0, preserveAspectRatio: true))
                context.drawPDFPage(page)
                context.restoreGState()
            }
            let overlayLines = replaceByPage[index] ? recognizedLinesByPage[index] : missingByPage[index]
            for line in overlayLines {
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
        let status = [replacements > 0 ? "Apple OCR replaced old OCR text on \(replacements) scan \(replacements == 1 ? "page" : "pages")" : nil,
            additions > 0 ? "added missing text on \(additions) \(additions == 1 ? "page" : "pages")" : nil]
            .compactMap { $0 }.joined(separator: "; ")
        return OCRPayload(url: target, preferredPages: preferredPages, status: status)
    }

    private static func renderPage(_ page: CGPDFPage, maxPixels: CGFloat,
                                   maxScale: CGFloat) throws -> CGImage {
        let crop = page.getBoxRect(.cropBox)
        let rotated = abs(page.rotationAngle) % 180 == 90
        let width = rotated ? crop.height : crop.width
        let height = rotated ? crop.width : crop.height
        let scale = min(maxScale, sqrt(maxPixels / max(1, width * height)))
        let pixelWidth = max(1, Int(width * scale))
        let pixelHeight = max(1, Int(height * scale))
        guard let bitmap = CGContext(data: nil, width: pixelWidth, height: pixelHeight,
            bitsPerComponent: 8, bytesPerRow: pixelWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
            throw PipeError.message("Not enough memory to render this scan page.")
        }
        bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
        bitmap.fill(CGRect(x: 0, y: 0, width: pixelWidth, height: pixelHeight))
        bitmap.concatenate(rasterTransform(for: page, pixelWidth: pixelWidth,
            pixelHeight: pixelHeight, scale: scale))
        bitmap.drawPDFPage(page)
        guard let image = bitmap.makeImage() else {
            throw PipeError.message("Cannot render this scan page.")
        }
        // ImageIO-backed JPEG is passed through by the PDF context, avoiding
        // an enormous lossless bitmap for what was already a scanned page.
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data,
            UTType.jpeg.identifier as CFString, 1, nil) else {
            throw PipeError.message("Cannot encode this scan page.")
        }
        CGImageDestinationAddImage(destination, image,
            [kCGImageDestinationLossyCompressionQuality: 0.92] as CFDictionary)
        guard CGImageDestinationFinalize(destination),
              let source = CGImageSourceCreateWithData(data, nil),
              let compressed = CGImageSourceCreateImageAtIndex(source, 0, nil) else {
            throw PipeError.message("Cannot prepare this scan page for PDF.")
        }
        return compressed
    }
}
