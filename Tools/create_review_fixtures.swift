// Build against a Debug app module with @testable access; see docs/ui-ux-review.md.
import AppKit
import CryptoKit
import Foundation
import SwiftData
@testable import DocNest

@main
struct ReviewFixtures {
    @MainActor
    static func main() throws {
        guard CommandLine.arguments.count == 3,
              let count = Int(CommandLine.arguments[2]), (0...2000).contains(count) else {
            fatalError("Usage: create-review-fixtures /tmp/Name.docnestlibrary document-count (0...2000)")
        }
        let url = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
        guard !FileManager.default.fileExists(atPath: url.path) else {
            fatalError("Choose a new path; existing libraries are never overwritten.")
        }
        let library = try DocumentLibraryService.createLibrary(at: url)
        let container = try DocumentLibraryService.openModelContainer(for: library)
        let context = container.mainContext
        let group = LabelGroup(name: "Personal")
        let finance = LabelTag(name: "Finance", unitSymbol: "€", colorName: "green", groupID: group.id)
        let tax = LabelTag(name: "Tax 2026", colorName: "orange", sortOrder: 1, groupID: group.id)
        let reference = LabelTag(name: "Reference", colorName: "blue", sortOrder: 2)
        let location = DocumentLocation(name: "Office · Shelf A")
        if count > 0 {
            context.insert(group); context.insert(finance); context.insert(tax)
            context.insert(reference); context.insert(location)
            context.insert(SmartFolder(name: "Finance & Tax", labelIDs: [finance.id, tax.id]))
        }
        let titles = ["Invoice October 2026", "A long document title to inspect truncation in compact windows", "Insurance Policy", "Consulting Agreement", "Tax Summary", "Travel Receipt", "Home Inventory", "Reference Notes", "Warranty Certificate", "Medical Receipt", "Archive Index", "Missing Original"]
        let date = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 9))!
        for index in 0..<count {
            let title = count > titles.count ? "Document \(String(format: "%04d", index + 1)) · \(titles[index % titles.count])" : titles[index % titles.count]
            let relativePath = "Originals/review-\(index + 1).pdf"
            let pdfURL = library.appendingPathComponent(relativePath)
            let data = pdf(title: title, index: index)
            if index != 11 { try data.write(to: pdfURL) }
            let record = DocumentRecord(
                originalFileName: pdfURL.lastPathComponent, title: title,
                documentDate: date.addingTimeInterval(Double(-index) * 86400),
                importedAt: date.addingTimeInterval(Double(-index) * 120),
                pageCount: 1, fileSize: Int64(data.count),
                contentHash: SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(),
                storedFilePath: relativePath,
                availability: index.isMultiple(of: 3) ? .physical : .digitalOnly,
                physicalLocationID: index.isMultiple(of: 3) ? location.id : nil,
                labels: index.isMultiple(of: 2) ? [finance, tax] : [reference]
            )
            record.ocrCompleted = true
            record.fullText = "\(title) Review fixture \(index)"
            context.insert(record)
            if index.isMultiple(of: 2) {
                context.insert(DocumentLabelValue(documentID: record.id, labelID: finance.id, decimalString: "\((index + 1) * 125).50"))
            }
        }
        try context.save()
        print("Created \(count) disposable review documents at \(library.path)")
    }

    private static func pdf(title: String, index: Int) -> Data {
        let data = NSMutableData()
        var bounds = CGRect(x: 0, y: 0, width: 595, height: 842)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &bounds, nil)!
        context.beginPDFPage(nil)
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        (title as NSString).draw(in: CGRect(x: 50, y: 650, width: 490, height: 130), withAttributes: [.font: NSFont.systemFont(ofSize: 26), .foregroundColor: NSColor.black])
        ("DocNest review fixture\nDate: 09 October 2026\nReference: DN-\(index + 1)\nDisposable sample for layout and workflow testing." as NSString).draw(in: CGRect(x: 50, y: 420, width: 490, height: 160), withAttributes: [.font: NSFont.systemFont(ofSize: 15), .foregroundColor: NSColor.black])
        NSGraphicsContext.restoreGraphicsState()
        context.endPDFPage(); context.closePDF()
        return data as Data
    }
}
