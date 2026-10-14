import CoreGraphics

/// Conservative structural evidence about the imported PDF, before Apple OCR
/// changes its searchable text. Ambiguous pages are never called digital-native.
enum PDFPageOrigin {
    enum Kind: Sendable, Equatable {
        case digital, scanned, mixed, unclear
    }

    static func kind(on page: CGPDFPage) -> Kind { PageScan(page: page).inspect().kind }

    static func hasReplaceableOCR(on page: CGPDFPage) -> Bool {
        PageScan(page: page).inspect().replaceableOCR
    }

    private struct Evidence {
        var kind: Kind
        var replaceableOCR: Bool
    }

    private final class PageScan {
        let page: CGPDFPage
        var transform = CGAffineTransform.identity
        var saved: [(CGAffineTransform, Int)] = []
        var textMode = 0
        var invisibleShows = 0
        var visibleShows = 0
        var coversPage = false
        var imageCoverage: CGFloat = 0
        var hasOpaqueDrawingObject = false

        init(page: CGPDFPage) { self.page = page }

        func inspect() -> Evidence {
            guard let table = CGPDFOperatorTableCreate() else {
                return Evidence(kind: .unclear, replaceableOCR: false)
            }
            defer { CGPDFOperatorTableRelease(table) }
            CGPDFOperatorTableSetCallback(table, "q", { _, info in PageScan.state(info)?.save() })
            CGPDFOperatorTableSetCallback(table, "Q", { _, info in PageScan.state(info)?.restore() })
            CGPDFOperatorTableSetCallback(table, "cm", { scanner, info in PageScan.state(info)?.matrix(scanner) })
            CGPDFOperatorTableSetCallback(table, "Tr", { scanner, info in PageScan.state(info)?.renderMode(scanner) })
            for name in ["Tj", "TJ", "'", "\""] {
                CGPDFOperatorTableSetCallback(table, name, { _, info in PageScan.state(info)?.textShown() })
            }
            CGPDFOperatorTableSetCallback(table, "Do", { scanner, info in PageScan.state(info)?.drawObject(scanner) })
            let content = CGPDFContentStreamCreateWithPage(page)
            let scanner = CGPDFScannerCreate(content, table, Unmanaged.passUnretained(self).toOpaque())
            defer { CGPDFScannerRelease(scanner) }
            guard CGPDFScannerScan(scanner), !hasOpaqueDrawingObject else {
                return Evidence(kind: .unclear, replaceableOCR: false)
            }
            let kind: Kind
            if coversPage || imageCoverage >= 0.8 {
                kind = visibleShows > 0 ? .mixed : .scanned
            } else if visibleShows > 0 {
                kind = invisibleShows > 0 || imageCoverage >= 0.25 ? .mixed : .digital
            } else {
                kind = .unclear
            }
            return Evidence(kind: kind,
                replaceableOCR: coversPage && invisibleShows > 0 && visibleShows == 0)
        }

        private static func state(_ info: UnsafeMutableRawPointer?) -> PageScan? {
            info.map { Unmanaged<PageScan>.fromOpaque($0).takeUnretainedValue() }
        }

        private func save() { saved.append((transform, textMode)) }
        private func restore() {
            guard let previous = saved.popLast() else { return }
            (transform, textMode) = previous
        }

        private func matrix(_ scanner: CGPDFScannerRef) {
            var numbers = [CGPDFReal](repeating: 0, count: 6)
            for index in numbers.indices.reversed() {
                guard CGPDFScannerPopNumber(scanner, &numbers[index]) else { return }
            }
            let matrix = CGAffineTransform(a: numbers[0], b: numbers[1], c: numbers[2],
                d: numbers[3], tx: numbers[4], ty: numbers[5])
            transform = matrix.concatenating(transform)
        }

        private func renderMode(_ scanner: CGPDFScannerRef) {
            var mode: CGPDFInteger = 0
            if CGPDFScannerPopInteger(scanner, &mode) { textMode = mode }
        }

        private func textShown() {
            if textMode == 3 { invisibleShows += 1 } else { visibleShows += 1 }
        }

        private func drawObject(_ scanner: CGPDFScannerRef) {
            var name: UnsafePointer<CChar>?
            guard CGPDFScannerPopName(scanner, &name), let name,
                  let resource = CGPDFContentStreamGetResource(CGPDFScannerGetContentStream(scanner),
                    "XObject", name) else {
                hasOpaqueDrawingObject = true
                return
            }
            var stream: CGPDFStreamRef?
            guard CGPDFObjectGetValue(resource, .stream, &stream), let stream,
                  let dictionary = CGPDFStreamGetDictionary(stream) else {
                hasOpaqueDrawingObject = true
                return
            }
            var subtype: UnsafePointer<CChar>?
            guard CGPDFDictionaryGetName(dictionary, "Subtype", &subtype),
                  let subtype, String(cString: subtype) == "Image" else {
                // A Form XObject may contain visible native text that the page
                // operator scan cannot see. Keep that page unchanged.
                hasOpaqueDrawingObject = true
                return
            }
            let imageBox = CGRect(x: 0, y: 0, width: 1, height: 1).applying(transform).standardized
            let pageBox = page.getBoxRect(.cropBox)
            guard !pageBox.isEmpty else { return }
            let overlap = imageBox.intersection(pageBox)
            guard !overlap.isNull else { return }
            let fraction = overlap.width * overlap.height / (pageBox.width * pageBox.height)
            imageCoverage += fraction
            coversPage = coversPage || fraction >= 0.85
        }
    }
}

struct DocumentOrigin: Sendable {
    enum Kind: Sendable, Equatable { case digital, scanned, mixed, unclear }

    let kind: Kind
    let digitalPages: Int
    let scannedPages: Int
    let mixedPages: Int
    let unclearPages: Int
    let importedImage: Bool

    static func pdf(_ document: CGPDFDocument) -> DocumentOrigin {
        guard document.numberOfPages > 0 else { return .unclear }
        var counts = (digital: 0, scanned: 0, mixed: 0, unclear: 0)
        for index in 1...document.numberOfPages {
            guard let page = document.page(at: index) else { counts.unclear += 1; continue }
            switch PDFPageOrigin.kind(on: page) {
            case .digital: counts.digital += 1
            case .scanned: counts.scanned += 1
            case .mixed: counts.mixed += 1
            case .unclear: counts.unclear += 1
            }
        }
        let kind: Kind
        if counts.mixed > 0 || (counts.digital > 0 && counts.scanned > 0) {
            kind = .mixed
        } else if counts.unclear > 0 {
            kind = .unclear
        } else {
            kind = counts.scanned > 0 ? .scanned : .digital
        }
        return DocumentOrigin(kind: kind, digitalPages: counts.digital,
            scannedPages: counts.scanned, mixedPages: counts.mixed,
            unclearPages: counts.unclear, importedImage: false)
    }

    static let image = DocumentOrigin(kind: .scanned, digitalPages: 0,
        scannedPages: 1, mixedPages: 0, unclearPages: 0, importedImage: true)
    static let unclear = DocumentOrigin(kind: .unclear, digitalPages: 0,
        scannedPages: 0, mixedPages: 0, unclearPages: 0, importedImage: false)

    var title: String {
        if importedImage { return "Image import" }
        switch kind {
        case .digital: return "Likely digital PDF"
        case .scanned: return "Likely scanned PDF"
        case .mixed: return "Mixed content"
        case .unclear: return "Origin unclear"
        }
    }

    var symbol: String {
        if importedImage { return "photo" }
        switch kind {
        case .digital: return "doc.text"
        case .scanned: return "doc.viewfinder"
        case .mixed: return "square.on.square"
        case .unclear: return "questionmark.circle"
        }
    }

    var detail: String {
        if importedImage { return "Photo or scan converted to PDF." }
        switch kind {
        case .digital: return "Visible PDF text, without a page-size scan image."
        case .scanned: return "Page content is mainly an image."
        case .mixed:
            let parts = [(digitalPages, "digital"), (scannedPages, "scanned"),
                (mixedPages, "mixed"), (unclearPages, "unclear")].compactMap { count, name in
                    count > 0 ? "\(count) \(name)" : nil
                }
            return parts.joined(separator: " · ") + " \(digitalPages + scannedPages + mixedPages == 1 ? "page" : "pages")"
        case .unclear: return "The PDF structure does not identify its origin reliably."
        }
    }
}
