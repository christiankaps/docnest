import CoreGraphics
import Foundation
import OSLog
import PDFKit
import Vision

enum OCRBackend: String, CaseIterable, Identifiable {
    case automatic
    case vision
    case ocrmypdf

    static let defaultsKey = "ocrBackend"

    var id: String { rawValue }

    var title: String {
        switch self {
        case .automatic: "Automatic"
        case .vision: "Apple Vision"
        case .ocrmypdf: "OCRmyPDF"
        }
    }

    var summary: String {
        switch self {
        case .automatic:
            "Use embedded PDF text when available, OCRmyPDF for scanned PDFs when installed, and Vision as fallback."
        case .vision:
            "Use the built-in PDFKit plus Vision pipeline for all OCR work."
        case .ocrmypdf:
            "Prefer OCRmyPDF and fall back to Vision if the external toolchain is unavailable."
        }
    }

    var availabilityDescription: String {
        switch self {
        case .automatic:
            if OCRTextExtractionService.isOCRmyPDFAvailable {
                return "Recommended. OCRmyPDF is available and will be used for image-only PDFs."
            }
            return "Recommended. OCRmyPDF is not fully available, so DocNest will stay on Vision."
        case .vision:
            return "Always available on supported macOS versions."
        case .ocrmypdf:
            return OCRTextExtractionService.isOCRmyPDFAvailable
                ? "Available. OCRmyPDF and Tesseract were found."
                : "Not fully available. Install OCRmyPDF and Tesseract or ensure they are on PATH."
        }
    }

    static var current: OCRBackend {
        guard let rawValue = UserDefaults.standard.string(forKey: defaultsKey),
              let backend = OCRBackend(rawValue: rawValue) else {
            return .automatic
        }
        return backend
    }
}

enum OCRTextExtractionService {
    private static let logger = Logger(subsystem: "com.kaps.docnest", category: "ocr")

    /// Rendering DPI for converting PDF pages to images for OCR.
    private static let renderDPI: CGFloat = 300.0
    static var isOCRmyPDFAvailable: Bool {
        ocrmyPDFExecutableURL() != nil && tesseractExecutableURL() != nil
    }

    /// Extracts text from a PDF, combining PDFKit fast path with Vision OCR fallback.
    /// Returns `nil` only when the document has zero pages.
    /// Returns an empty string when OCR produces no text (genuinely blank pages).
    static func extractText(from pdfDocument: PDFDocument, sourceURL: URL? = nil) async -> String? {
        guard pdfDocument.pageCount > 0 else { return nil }

        switch OCRBackend.current {
        case .automatic:
            if let sourceURL, !containsEmbeddedText(in: pdfDocument),
               let text = await extractTextWithOCRmyPDF(from: sourceURL) {
                return text
            }
        case .vision:
            break
        case .ocrmypdf:
            if let sourceURL, let text = await extractTextWithOCRmyPDF(from: sourceURL) {
                return text
            }
        }

        return await extractTextWithVision(from: pdfDocument)
    }

    private static func extractTextWithVision(from pdfDocument: PDFDocument) async -> String? {
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

    private static func containsEmbeddedText(in pdfDocument: PDFDocument) -> Bool {
        for pageIndex in 0..<pdfDocument.pageCount {
            guard let page = pdfDocument.page(at: pageIndex) else { continue }
            if let pdfText = page.string, !pdfText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                return true
            }
        }

        return false
    }

    /// Uses OCRmyPDF for image-only PDFs when the executable is available locally.
    /// Returns `nil` if OCRmyPDF is unavailable or fails, allowing the caller to fall back.
    private static func extractTextWithOCRmyPDF(from sourceURL: URL) async -> String? {
        guard let executableURL = ocrmyPDFExecutableURL(),
              tesseractExecutableURL() != nil else { return nil }

        return await Task.detached(priority: .utility) {
            let fileManager = FileManager.default
            let temporaryDirectory = fileManager.temporaryDirectory.appendingPathComponent(
                "docnest-ocrmypdf-\(UUID().uuidString)",
                isDirectory: true
            )
            let sidecarURL = temporaryDirectory.appendingPathComponent("output.txt")

            do {
                try fileManager.createDirectory(at: temporaryDirectory, withIntermediateDirectories: true)
                defer {
                    try? fileManager.removeItem(at: temporaryDirectory)
                }

                let process = Process()
                process.executableURL = executableURL
                process.environment = ocrToolEnvironment()
                process.arguments = [
                    "--skip-text",
                    "--output-type", "none",
                    "--sidecar", sidecarURL.path,
                    "--quiet",
                    sourceURL.path,
                    "-"
                ]

                let outputPipe = Pipe()
                process.standardOutput = outputPipe
                process.standardError = outputPipe

                try process.run()
                process.waitUntilExit()

                guard process.terminationStatus == 0 else {
                    let message = String(data: outputPipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?
                        .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
                    if !message.isEmpty {
                        logger.warning("OCRmyPDF failed: \(message, privacy: .public)")
                    }
                    return nil
                }

                guard fileManager.fileExists(atPath: sidecarURL.path) else {
                    logger.warning("OCRmyPDF completed without creating a sidecar text file")
                    return nil
                }

                let text = try String(contentsOf: sidecarURL, encoding: .utf8)
                return text.trimmingCharacters(in: .whitespacesAndNewlines)
            } catch {
                logger.warning("OCRmyPDF execution failed: \(error.localizedDescription, privacy: .public)")
                return nil
            }
        }.value
    }

    private static func ocrmyPDFExecutableURL() -> URL? {
        let fileManager = FileManager.default
        let candidates: [String] = [
            "/opt/homebrew/bin/ocrmypdf",
            "/usr/local/bin/ocrmypdf",
            "/usr/bin/ocrmypdf"
        ]

        for candidate in candidates where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        let pathEntries = (ProcessInfo.processInfo.environment["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for pathEntry in pathEntries {
            let candidate = URL(fileURLWithPath: pathEntry).appendingPathComponent("ocrmypdf").path
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return nil
    }

    private static func tesseractExecutableURL() -> URL? {
        executableURL(named: "tesseract", preferredPaths: [
            "/opt/homebrew/bin/tesseract",
            "/usr/local/bin/tesseract",
            "/usr/bin/tesseract"
        ])
    }

    private static func ocrToolEnvironment() -> [String: String] {
        var environment = ProcessInfo.processInfo.environment
        let commonPaths = ["/opt/homebrew/bin", "/usr/local/bin", "/usr/bin", "/bin"]
        let existingPaths = Set((environment["PATH"] ?? "").split(separator: ":").map(String.init))
        let mergedPaths = commonPaths + existingPaths.filter { !commonPaths.contains($0) }
        environment["PATH"] = mergedPaths.joined(separator: ":")
        return environment
    }

    private static func executableURL(named name: String, preferredPaths: [String]) -> URL? {
        let fileManager = FileManager.default

        for candidate in preferredPaths where fileManager.isExecutableFile(atPath: candidate) {
            return URL(fileURLWithPath: candidate)
        }

        let pathEntries = (ocrToolEnvironment()["PATH"] ?? "")
            .split(separator: ":")
            .map(String.init)
        for pathEntry in pathEntries {
            let candidate = URL(fileURLWithPath: pathEntry).appendingPathComponent(name).path
            if fileManager.isExecutableFile(atPath: candidate) {
                return URL(fileURLWithPath: candidate)
            }
        }

        return nil
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
