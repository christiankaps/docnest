import AppKit
import SwiftData
import SwiftUI

/// Encodes label drag payloads used inside DocNest sidebar and document views.
enum DocumentLabelDragPayload {
    static let prefix = "docnest-label:"

    static func payload(for labelID: UUID) -> String {
        "\(prefix)\(labelID.uuidString)"
    }

    static func labelID(from payload: String) -> UUID? {
        guard payload.hasPrefix(prefix) else {
            return nil
        }

        let rawID = String(payload.dropFirst(prefix.count))
        return UUID(uuidString: rawID)
    }
}

/// Shared helpers for document drags that must work both inside DocNest and in Finder.
///
/// Internal drops use a lightweight string payload so label assignment and other
/// in-app behaviors can continue to work. External drags snapshot plain export
/// metadata first and only materialize temporary files when AppKit actually
/// starts the drag session.
enum DocumentDragHelper {
    /// Builds the internal payload string for dragging documents.
    static func internalPayload(
        for document: DocumentRecord,
        selectedIDs: Set<PersistentIdentifier>,
        selectedDocumentIDsToDrag: [UUID]
    ) -> String {
        let documentIDsToDrag: [UUID]

        if selectedIDs.contains(document.persistentModelID) {
            documentIDsToDrag = selectedDocumentIDsToDrag
        } else {
            documentIDsToDrag = [document.id]
        }

        return DocumentFileDragPayload.payload(for: documentIDsToDrag)
    }

    /// Snapshot of everything the drag handle needs after SwiftUI has rendered.
    ///
    /// `payload` is the in-app drag contract. `exportItems` is the Finder-facing
    /// export snapshot captured before AppKit drag callbacks run.
    struct DragSession {
        let payload: String
        let exportItems: [ExportDocumentsUseCase.DragExportItem]
    }
}

/// Encodes the internal document drag payload understood by DocNest drop targets.
///
/// The payload is intentionally string-based so SwiftUI drop destinations can
/// parse it without depending on AppKit file promises.
enum DocumentFileDragPayload {
    static let prefix = "docnest-documents:"

    static func payload(for documentIDs: [UUID]) -> String {
        let rawIDs = documentIDs.map(\.uuidString).joined(separator: ",")
        return "\(prefix)\(rawIDs)"
    }

    static func documentIDs(from payload: String) -> [UUID]? {
        guard payload.hasPrefix(prefix) else {
            return nil
        }

        let rawIDs = payload.dropFirst(prefix.count).split(separator: ",")
        let documentIDs = rawIDs.compactMap { UUID(uuidString: String($0)) }
        guard !documentIDs.isEmpty else {
            return nil
        }

        return documentIDs
    }
}

/// AppKit-backed drag handle used for document drags to Finder and other apps.
///
/// SwiftUI's standard file drag support did not fit DocNest's mixed internal and
/// external drag contract, so this bridge creates the AppKit dragging session
/// directly. Temporary export files are materialized only once the user actually
/// starts dragging.
struct DocumentDragHandleView: NSViewRepresentable {
    let session: DocumentDragHelper.DragSession?

    func makeNSView(context: Context) -> DragHandleNSView {
        let view = DragHandleNSView()
        view.toolTip = "Drag document"
        return view
    }

    func updateNSView(_ nsView: DragHandleNSView, context: Context) {
        nsView.session = session
    }

    final class DragHandleNSView: NSView, NSDraggingSource {
        var session: DocumentDragHelper.DragSession?
        private var dragHasStarted = false

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
        }

        @available(*, unavailable)
        required init?(coder: NSCoder) {
            nil
        }

        override func draw(_ dirtyRect: NSRect) {
            super.draw(dirtyRect)

            let image = NSImage(systemSymbolName: "line.3.horizontal", accessibilityDescription: nil)
            image?.isTemplate = true
            NSColor.tertiaryLabelColor.set()
            image?.draw(
                in: bounds.insetBy(dx: 2, dy: 4),
                from: .zero,
                operation: .sourceOver,
                fraction: 1
            )
        }

        override func mouseDown(with event: NSEvent) {
            dragHasStarted = false
        }

        override func mouseDragged(with event: NSEvent) {
            guard !dragHasStarted, let session else { return }
            dragHasStarted = true

            let draggingItems = makeDraggingItems(for: session)
            guard !draggingItems.isEmpty else { return }

            let draggingSession = beginDraggingSession(with: draggingItems, event: event, source: self)
            draggingSession.animatesToStartingPositionsOnCancelOrFail = true
        }

        override func mouseUp(with event: NSEvent) {
            dragHasStarted = false
        }

        func draggingSession(
            _ session: NSDraggingSession,
            sourceOperationMaskFor context: NSDraggingContext
        ) -> NSDragOperation {
            .copy
        }

        func ignoreModifierKeys(for session: NSDraggingSession) -> Bool {
            true
        }

        private func makeDraggingItems(for session: DocumentDragHelper.DragSession) -> [NSDraggingItem] {
            let previewImage = NSImage(systemSymbolName: "doc.richtext", accessibilityDescription: nil)
            let draggingFrame = bounds
            guard let exportedURLs = try? ExportDocumentsUseCase.temporaryExportURLs(for: session.exportItems),
                  !exportedURLs.isEmpty else {
                return []
            }

            return exportedURLs.enumerated().map { index, fileURL in
                let pasteboardItem = NSPasteboardItem()
                pasteboardItem.setString(fileURL.absoluteString, forType: .fileURL)
                if index == 0 {
                    pasteboardItem.setString(session.payload, forType: .string)
                }

                let draggingItem = NSDraggingItem(pasteboardWriter: pasteboardItem)
                let offsetFrame = draggingFrame.offsetBy(dx: CGFloat(index * 4), dy: CGFloat(-index * 2))
                draggingItem.setDraggingFrame(offsetFrame, contents: previewImage)
                return draggingItem
            }
        }
    }
}
