import AppKit
import QuickLookUI
import SwiftUI

/// An invisible NSViewRepresentable whose sole purpose is to participate in
/// the responder chain so that `QLPreviewPanel` can discover a willing
/// controller when walking up from the key window's first responder.
struct QuickLookPanelResponder: NSViewControllerRepresentable {
    let coordinator: QuickLookCoordinator

    func makeNSViewController(context: Context) -> QuickLookResponderController {
        QuickLookResponderController(coordinator: coordinator)
    }

    func updateNSViewController(_ controller: QuickLookResponderController, context: Context) {
        controller.coordinator = coordinator
    }
}

final class QuickLookResponderController: NSViewController {
    var coordinator: QuickLookCoordinator

    init(coordinator: QuickLookCoordinator) {
        self.coordinator = coordinator
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        view = NSView()
    }

    override func acceptsPreviewPanelControl(_ panel: QLPreviewPanel!) -> Bool {
        !coordinator.previewURLs.isEmpty
    }

    override func beginPreviewPanelControl(_ panel: QLPreviewPanel!) {
        panel.dataSource = coordinator.panelDataSource
    }

    override func endPreviewPanelControl(_ panel: QLPreviewPanel!) {
        // Keep dataSource alive — the coordinator manages the lifecycle.
    }
}
