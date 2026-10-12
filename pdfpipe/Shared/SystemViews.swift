import SwiftUI
import PDFKit
import UniformTypeIdentifiers

struct PDFPreview: UIViewRepresentable {
    var url: URL
    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.backgroundColor = .secondarySystemBackground
        return view
    }
    func updateUIView(_ view: PDFView, context: Context) {
        if view.document?.documentURL != url { view.document = PDFDocument(url: url) }
    }
}

struct ExportPicker: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool, String?) -> Void
    @Environment(\.dismiss) private var dismiss
    func makeCoordinator() -> Coordinator { Coordinator(self) }
    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forExporting: [url], asCopy: true)
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}
    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        let parent: ExportPicker
        init(_ parent: ExportPicker) { self.parent = parent }
        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            parent.completion(true, urls.first?.lastPathComponent)
            parent.dismiss()
        }
        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.completion(false, nil)
            parent.dismiss()
        }
    }
}

struct SharePicker: UIViewControllerRepresentable {
    let url: URL
    let completion: (Bool, String?) -> Void
    func makeUIViewController(context: Context) -> UIActivityViewController {
        let provider = NSItemProvider()
        provider.registerFileRepresentation(forTypeIdentifier: UTType.pdf.identifier, fileOptions: [], visibility: .all) { completion in
            completion(url, false, nil)
            return nil
        }
        provider.suggestedName = url.lastPathComponent
        let items = UIActivityItemsConfiguration(itemProviders: [provider])
        items.metadataProvider = { key in key == .title ? url.lastPathComponent : nil }
        let controller = UIActivityViewController(activityItemsConfiguration: items)
        controller.completionWithItemsHandler = { _, completed, _, error in
            let canceled = (error as NSError?)?.domain == NSCocoaErrorDomain && (error as NSError?)?.code == NSUserCancelledError
            completion(completed, canceled ? nil : error?.localizedDescription)
        }
        return controller
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}
