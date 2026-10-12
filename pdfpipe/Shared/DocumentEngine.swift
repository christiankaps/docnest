import Foundation
import PDFKit
import Vision
import ImageIO
import CoreText
import UniformTypeIdentifiers

struct DocumentFacts: Sendable {
    var filename: String
    var originalBasename: String
    var sourceFormat: String
    var bytes: Int64
    var pages: Int
    var dimensions: String
    var hasText: Bool
}

struct SessionDocument: Sendable {
    var url: URL
    var facts: DocumentFacts
    var report: [String]
}

struct PreparedRun: Sendable {
    var url: URL
    var report: [String]
    var processedAt: Date
    var analysis: DocumentAnalysis
}

actor DocumentEngine {
    static let maximumBytes: Int64 = 30 * 1024 * 1024
    static let maximumPages = 50
    private let session: TemporarySession
    private var input: URL?
    private var sourceName = "Document"
    private var sourceFormat = "PDF"

    init(session: TemporarySession) { self.session = session }

    /// Runs inside an item-provider callback, while its temporary URL remains valid.
    nonisolated static func stage(_ source: URL, to directory: URL) throws -> URL {
        guard source.isFileURL else { throw PipeError.message("Share a PDF, JPEG, or PNG file, rather than a web link.") }
        let access = source.startAccessingSecurityScopedResource()
        defer { if access { source.stopAccessingSecurityScopedResource() } }
        let target = directory.appendingPathComponent("incoming").appendingPathExtension(source.pathExtension)
        let coordinator = NSFileCoordinator()
        var coordinationError: NSError?
        var failure: Error?
        coordinator.coordinate(readingItemAt: source, options: .withoutChanges, error: &coordinationError) { readable in
            do {
                let values = try readable.resourceValues(forKeys: [.fileSizeKey, .isRegularFileKey])
                guard values.isRegularFile == true else { throw PipeError.message("Import a single regular document file.") }
                guard Int64(values.fileSize ?? 0) <= maximumBytes else { throw PipeError.message("Files must be 30 MB or smaller.") }
                // Stream rather than trusting size metadata or loading the whole source in memory.
                FileManager.default.createFile(atPath: target.path, contents: nil)
                let reader = try FileHandle(forReadingFrom: readable)
                defer { try? reader.close() }
                let writer = try FileHandle(forWritingTo: target)
                defer { try? writer.close() }
                var total: Int64 = 0
                let deadline = Date().addingTimeInterval(30)
                while let chunk = try reader.read(upToCount: 256 * 1024), !chunk.isEmpty {
                    try Task.checkCancellation()
                    total += Int64(chunk.count)
                    guard total <= maximumBytes, Date() < deadline else {
                        throw PipeError.message("Import exceeded the 30 MB size or 30-second time limit.")
                    }
                    try writer.write(contentsOf: chunk)
                }
            } catch { failure = error }
        }
        if let failure { try? FileManager.default.removeItem(at: target); throw failure }
        if let coordinationError { try? FileManager.default.removeItem(at: target); throw coordinationError }
        return target
    }

    func prepare(staged: URL, originalName: String) throws -> SessionDocument {
        try Task.checkCancellation()
        sourceName = (originalName as NSString).deletingPathExtension
        if sourceName.isEmpty { sourceName = "Document" }
        let pdf = session.directory.appendingPathComponent("input.pdf")
        if let document = PDFDocument(url: staged) {
            try validate(document)
            try FileManager.default.copyItem(at: staged, to: pdf)
            sourceFormat = "PDF"
        } else {
            guard let imageSource = CGImageSourceCreateWithURL(staged as CFURL, nil),
                  let type = CGImageSourceGetType(imageSource) as String?,
                  type == UTType.jpeg.identifier || type == UTType.png.identifier else {
                throw PipeError.message("Supported files are readable PDFs, JPEGs, and PNGs.")
            }
            let properties = CGImageSourceCopyPropertiesAtIndex(imageSource, 0, nil) as? [CFString: Any]
            let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.doubleValue ?? 0
            let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.doubleValue ?? 0
            guard width > 0, height > 0, width * height <= 40_000_000 else {
                throw PipeError.message("Images must contain at most 40 million pixels.")
            }
            let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceThumbnailMaxPixelSize: 4096, kCGImageSourceCreateThumbnailWithTransform: true]
            guard let image = CGImageSourceCreateThumbnailAtIndex(imageSource, 0, options as CFDictionary) else {
                throw PipeError.message("This image could not be decoded.")
            }
            let size = CGSize(width: CGFloat(image.width) * 0.5, height: CGFloat(image.height) * 0.5)
            var box = CGRect(origin: .zero, size: size)
            guard let context = CGContext(pdf as CFURL, mediaBox: &box, nil) else { throw PipeError.message("Cannot create the converted PDF.") }
            context.beginPDFPage(nil)
            context.draw(image, in: box)
            context.endPDFPage()
            context.closePDF()
            sourceFormat = type == UTType.jpeg.identifier ? "JPEG" : "PNG"
        }
        try Task.checkCancellation()
        input = pdf
        return try describe(pdf, filename: originalName, report: sourceFormat == "PDF" ? [] : ["Converted \(sourceFormat) to PDF"])
    }

    private func validate(_ document: PDFDocument) throws {
        guard !document.isEncrypted, !document.isLocked else { throw PipeError.message("Encrypted PDFs are not supported in this MVP. Export an unlocked copy first.") }
        guard document.pageCount > 0, document.pageCount <= Self.maximumPages else {
            throw PipeError.message("PDFs must have between 1 and 50 pages.")
        }
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { throw PipeError.message("A PDF page could not be read.") }
            let box = page.bounds(for: .cropBox)
            guard box.minX.isFinite, box.minY.isFinite, box.width.isFinite, box.height.isFinite, box.width > 0, box.height > 0,
                  box.width <= 14_400, box.height <= 14_400 else {
                throw PipeError.message("A PDF page has unsupported dimensions.")
            }
        }
    }

    private func describe(_ url: URL, filename: String, report: [String]) throws -> SessionDocument {
        guard let pdf = PDFDocument(url: url), let page = pdf.page(at: 0) else { throw PipeError.message("The PDF result could not be opened.") }
        let rect = page.bounds(for: .cropBox)
        let bytes = Int64(try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0)
        return .init(url: url, facts: .init(filename: filename, originalBasename: sourceName, sourceFormat: sourceFormat, bytes: bytes,
            pages: pdf.pageCount, dimensions: "\(Int(rect.width)) × \(Int(rect.height)) pt (first page)",
            hasText: (0..<pdf.pageCount).contains { !(pdf.page(at: $0)?.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true) }), report: report)
    }

    func process(_ pipeline: Pipeline, text: String, date: Date = Date(),
                 progress: @Sendable (String) async -> Void) async throws -> SessionDocument {
        let prepared = try await prepareRun(pipeline, text: text, date: date, progress: progress)
        return try finishRun(prepared, pipeline: pipeline,
            values: .init(original: sourceName, manualText: text, processedAt: date,
                documentDate: prepared.analysis.date.value,
                dateAmbiguous: prepared.analysis.date.isAmbiguous,
                words: prepared.analysis.words.map(\.text)))
    }

    func prepareRun(_ pipeline: Pipeline, text: String = "", date: Date = Date(),
                    progress: @Sendable (String) async -> Void) async throws -> PreparedRun {
        try pipeline.validate()
        guard let input else { throw PipeError.message("Import a document first.") }
        if !pipeline.needsAnalysis {
            _ = try pipeline.outputFilename(original: sourceName, text: text, date: date)
        }
        var output = input
        var report = sourceFormat == "PDF" ? [] : ["Converted \(sourceFormat) to PDF"]
        let deadline = Date().addingTimeInterval(120)
        for step in pipeline.steps where step.kind == .ocr {
            try Task.checkCancellation()
            let next = session.directory.appendingPathComponent("ocr-\(UUID().uuidString).pdf")
            let count = try await ocr(output, to: next, deadline: deadline,
                skipExistingText: step.skipExistingText, progress: progress)
            output = next
            report.append("OCR processed \(count) pages" + (step.skipExistingText ? "; existing text pages kept" : "; all pages recognized"))
        }
        try Task.checkCancellation()
        let analysis = pipeline.needsAnalysis ? try DocumentAnalyzer.analyze(output) : .empty
        return .init(url: output, report: report, processedAt: date, analysis: analysis)
    }

    func finishRun(_ prepared: PreparedRun, pipeline: Pipeline, values: NamingValues,
                   overrideFilename: String? = nil) throws -> SessionDocument {
        try Task.checkCancellation()
        let filename = try overrideFilename.map(FilenameTemplate.filename) ?? pipeline.outputFilename(values: values)
        let resultDirectory = session.directory.appendingPathComponent("output-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: resultDirectory, withIntermediateDirectories: true)
        let result = resultDirectory.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: prepared.url, to: result)
        let report = prepared.report + (pipeline.steps.contains { $0.kind == .rename } ? ["Renamed to \(filename)"] : [])
        return try describe(result, filename: filename, report: report)
    }

    func preview(_ prepared: PreparedRun) throws -> SessionDocument {
        try describe(prepared.url, filename: sourceName + ".pdf", report: prepared.report)
    }

    func renameResult(_ document: SessionDocument, name: String) throws -> SessionDocument {
        let filename = try FilenameTemplate.filename(name)
        let target = document.url.deletingLastPathComponent().appendingPathComponent(filename)
        if target != document.url { try FileManager.default.moveItem(at: document.url, to: target) }
        return try describe(target, filename: filename, report: document.report)
    }

    private func ocr(_ source: URL, to target: URL, deadline: Date, skipExistingText: Bool,
                     progress: @Sendable (String) async -> Void) async throws -> Int {
        guard let pdf = PDFDocument(url: source) else { throw PipeError.message("Cannot open the PDF for OCR.") }
        try validate(pdf)
        // Re-emitting pages cannot preserve editable annotations/forms or signatures.
        for index in 0..<pdf.pageCount {
            if !(pdf.page(at: index)?.annotations.isEmpty ?? true) {
                throw PipeError.message("OCR of annotated, signed, or form PDFs is not supported. Use a pipeline without OCR or share a flattened copy.")
            }
        }
        guard let cgDocument = CGPDFDocument(source as CFURL) else { throw PipeError.message("Cannot render this PDF.") }
        if let catalog = cgDocument.catalog {
            var form: CGPDFDictionaryRef?
            if CGPDFDictionaryGetDictionary(catalog, "AcroForm", &form) {
                throw PipeError.message("OCR of form or signed PDFs is not supported. Use a pipeline without OCR.")
            }
        }
        var initial = CGRect(x: 0, y: 0, width: 612, height: 792)
        guard let context = CGContext(target as CFURL, mediaBox: &initial, [kCGPDFContextCreator: "PDF Pipe"] as CFDictionary) else {
            throw PipeError.message("Cannot write the searchable PDF.")
        }
        var completed = false
        defer { context.closePDF(); if !completed { try? FileManager.default.removeItem(at: target) } }
        var recognizedPages = 0
        for index in 0..<pdf.pageCount {
            try Task.checkCancellation()
            guard Date() < deadline else { throw PipeError.message("OCR reached its two-minute time limit. Try a shorter document.") }
            await progress("Making page \(index + 1) of \(pdf.pageCount) searchable…")
            guard let cgPage = cgDocument.page(at: index + 1), let page = pdf.page(at: index) else { throw PipeError.message("Cannot read a PDF page.") }
            try autoreleasepool {
                let crop = cgPage.getBoxRect(.cropBox)
                let rotated = abs(cgPage.rotationAngle) % 180 == 90
                let box = CGRect(x: 0, y: 0, width: rotated ? crop.height : crop.width, height: rotated ? crop.width : crop.height)
                context.beginPDFPage([kCGPDFContextMediaBox: NSData(bytes: [box], length: MemoryLayout<CGRect>.size)] as CFDictionary)
                let hasText = !(page.string?.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ?? true)
                if skipExistingText || !hasText {
                    context.saveGState()
                    context.concatenate(cgPage.getDrawingTransform(.cropBox, rect: box, rotate: 0, preserveAspectRatio: true))
                    context.drawPDFPage(cgPage)
                    context.restoreGState()
                }
                if !skipExistingText || !hasText {
                    let scale = min(2.5, sqrt(4_000_000 / (box.width * box.height)))
                    let width = max(1, Int(box.width * scale)), height = max(1, Int(box.height * scale))
                    guard let bitmap = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                        bytesPerRow: width * 4, space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else {
                        throw PipeError.message("Not enough memory to render this page.")
                    }
                    bitmap.setFillColor(CGColor(gray: 1, alpha: 1))
                    bitmap.fill(CGRect(x: 0, y: 0, width: width, height: height))
                    bitmap.concatenate(cgPage.getDrawingTransform(.cropBox,
                        rect: CGRect(x: 0, y: 0, width: width, height: height), rotate: 0, preserveAspectRatio: true))
                    bitmap.drawPDFPage(cgPage)
                    guard let image = bitmap.makeImage() else { throw PipeError.message("Cannot render the OCR page.") }
                    // Flatten an existing text layer before replacement so it is not duplicated.
                    if hasText { context.draw(image, in: box) }
                    let request = VNRecognizeTextRequest()
                    request.recognitionLevel = .accurate
                    request.usesLanguageCorrection = true
                    request.automaticallyDetectsLanguage = true
                    try VNImageRequestHandler(cgImage: image).perform([request])
                    try Task.checkCancellation()
                    guard Date() < deadline else { throw PipeError.message("OCR reached its two-minute time limit.") }
                    for observation in request.results ?? [] {
                        guard let candidate = observation.topCandidates(1).first else { continue }
                        let bounds = observation.boundingBox
                        let font = CTFontCreateWithName("Helvetica" as CFString, max(1, bounds.height * box.height), nil)
                        let line = CTLineCreateWithAttributedString(NSAttributedString(string: candidate.string,
                            attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]))
                        let lineWidth = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
                        guard lineWidth > 0 else { continue }
                        context.saveGState()
                        context.textMatrix = .identity
                        context.translateBy(x: bounds.minX * box.width, y: bounds.minY * box.height)
                        context.scaleBy(x: bounds.width * box.width / lineWidth, y: 1)
                        context.setTextDrawingMode(.invisible)
                        context.textPosition = .zero
                        CTLineDraw(line, context)
                        context.restoreGState()
                    }
                    recognizedPages += 1
                }
                context.endPDFPage()
            }
        }
        completed = true
        return recognizedPages
    }
}
