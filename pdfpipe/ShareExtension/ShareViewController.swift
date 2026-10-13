import UIKit
import SwiftUI
import UniformTypeIdentifiers

@MainActor
final class ShareViewController: UIViewController {
    private let settings = OneFlowSettingsStore()
    private let model = OneFlowSessionModel()
    private var started = false

    override func viewDidLoad() {
        super.viewDidLoad()
        let host = UIHostingController(rootView: OneFlowWorkbenchView(model: model, settings: settings))
        addChild(host)
        view.addSubview(host.view)
        host.view.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            host.view.leadingAnchor.constraint(equalTo: view.leadingAnchor),
            host.view.trailingAnchor.constraint(equalTo: view.trailingAnchor),
            host.view.topAnchor.constraint(equalTo: view.topAnchor),
            host.view.bottomAnchor.constraint(equalTo: view.bottomAnchor)
        ])
        host.didMove(toParent: self)
        model.onFinished = { [weak self] in
            guard let self else { return }
            if case .finished = model.phase { extensionContext?.completeRequest(returningItems: nil) }
            else { extensionContext?.cancelRequest(withError: NSError(domain: NSCocoaErrorDomain, code: NSUserCancelledError)) }
        }
    }

    override func viewDidAppear(_ animated: Bool) {
        super.viewDidAppear(animated)
        guard !started else { return }
        started = true
        settings.reload()
        let items = extensionContext?.inputItems.compactMap { $0 as? NSExtensionItem } ?? []
        let attachments = items.flatMap { $0.attachments ?? [] }
        guard attachments.count == 1, let provider = attachments.first else {
            model.error = "Share exactly one PDF, JPEG, or PNG file."
            return
        }
        model.importProvider(provider)
    }
}
