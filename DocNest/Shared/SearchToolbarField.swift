import AppKit
import SwiftUI

struct SearchToolbarField: NSViewRepresentable {
    @Binding var text: String
    let focusRequestToken: Int

    func makeCoordinator() -> Coordinator {
        Coordinator(text: $text)
    }

    func makeNSView(context: Context) -> NSSearchField {
        let searchField = NSSearchField(frame: .zero)
        searchField.delegate = context.coordinator
        searchField.placeholderString = "Search title, file name, or labels"
        searchField.sendsSearchStringImmediately = true
        searchField.sendsWholeSearchString = false
        searchField.setAccessibilityIdentifier("document-search-field")
        return searchField
    }

    func updateNSView(_ nsView: NSSearchField, context: Context) {
        context.coordinator.text = $text

        if nsView.stringValue != text {
            nsView.stringValue = text
        }

        guard context.coordinator.lastFocusRequestToken != focusRequestToken else {
            return
        }

        context.coordinator.lastFocusRequestToken = focusRequestToken
        Task { @MainActor in
            nsView.window?.makeFirstResponder(nsView)
            nsView.currentEditor()?.selectAll(nil)
        }
    }

    final class Coordinator: NSObject, NSSearchFieldDelegate {
        var text: Binding<String>
        var lastFocusRequestToken = 0

        init(text: Binding<String>) {
            self.text = text
        }

        func controlTextDidChange(_ notification: Notification) {
            guard let searchField = notification.object as? NSSearchField else {
                return
            }

            text.wrappedValue = searchField.stringValue
        }
    }
}
