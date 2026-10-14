import Foundation
import PDFKit
import ImageIO
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

struct AutomaticResult: Sendable {
    var document: SessionDocument
    var embeddedAnalysis: DocumentAnalysis
    var ocrAnalysis: DocumentAnalysis
    var text: TextSnapshot
    var status: String
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

    func processAutomatically(_ imported: SessionDocument,
        progress: @Sendable (String) async -> Void) async throws -> AutomaticResult {
        guard let input else { throw PipeError.message("Import a document first.") }
        let target = session.directory.appendingPathComponent("searchable.pdf")
        let outcome = try await AutomaticOCR.process(input, to: target, progress: progress)
        let report = imported.report + [outcome.status]
        return AutomaticResult(document: try describe(outcome.url, filename: imported.facts.filename, report: report),
            embeddedAnalysis: DocumentAnalyzer.analyze(pages: outcome.embeddedPages),
            ocrAnalysis: DocumentAnalyzer.analyze(pages: outcome.recognizedPages),
            text: TextSnapshot(embedded: outcome.embeddedText, ocr: outcome.recognizedText),
            status: outcome.status)
    }

    func readableFallback(_ imported: SessionDocument, reason: String) throws -> AutomaticResult {
        guard let pdf = PDFDocument(url: imported.url) else {
            throw PipeError.message("Cannot read the PDF text for filename analysis.")
        }
        let pages = try (0..<pdf.pageCount).map { index -> PDFPage in
            guard let page = pdf.page(at: index) else {
                throw PipeError.message("Cannot read a PDF page for filename analysis.")
            }
            return page
        }
        let analysis = DocumentAnalyzer.analyze(pages: pages.map(DocumentAnalyzer.extractPage))
        return AutomaticResult(document: imported, embeddedAnalysis: analysis, ocrAnalysis: .empty,
            text: TextSnapshot(embedded: pages.map { $0.string ?? "" },
                ocr: Array(repeating: "", count: pdf.pageCount)),
            status: "OCR could not add searchable text: \(reason)")
    }

    func exportCopy(_ document: SessionDocument, named name: String) throws -> URL {
        let filename = try SafeFilename.pdf(name)
        let folder = session.directory.appendingPathComponent("export-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let url = folder.appendingPathComponent(filename)
        try FileManager.default.copyItem(at: document.url, to: url)
        return url
    }

}
