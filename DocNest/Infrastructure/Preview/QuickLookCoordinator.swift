import AppKit
import QuickLookUI

@MainActor
@Observable
final class QuickLookCoordinator {
    var previewURLs: [URL] = []

    @ObservationIgnored private(set) var panelDataSource: QuickLookPanelDataSource!

    init() {
        panelDataSource = QuickLookPanelDataSource(coordinator: self)
    }

    func togglePreview() {
        guard !previewURLs.isEmpty else { return }
        let panel = QLPreviewPanel.shared()!
        if panel.isVisible {
            panel.orderOut(nil)
        } else {
            panel.dataSource = panelDataSource
            panel.reloadData()
            panel.makeKeyAndOrderFront(nil)
        }
    }

    func reloadIfVisible() {
        guard QLPreviewPanel.sharedPreviewPanelExists() else { return }
        let panel = QLPreviewPanel.shared()!
        guard panel.isVisible else { return }
        panel.dataSource = panelDataSource
        panel.reloadData()
    }
}

@MainActor
final class QuickLookPanelDataSource: NSObject, @preconcurrency QLPreviewPanelDataSource {
    unowned let coordinator: QuickLookCoordinator

    init(coordinator: QuickLookCoordinator) {
        self.coordinator = coordinator
    }

    func numberOfPreviewItems(in panel: QLPreviewPanel!) -> Int {
        coordinator.previewURLs.count
    }

    func previewPanel(_ panel: QLPreviewPanel!, previewItemAt index: Int) -> (any QLPreviewItem)! {
        coordinator.previewURLs[index] as NSURL
    }
}
