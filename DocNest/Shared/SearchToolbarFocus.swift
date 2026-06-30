import AppKit

/// Bridges the ⌘F "Find" command to the native `.searchable` toolbar field.
///
/// macOS 14 has no SwiftUI API to programmatically focus a `.searchable`
/// field (`searchFocused(_:)` is macOS 15+), so this locates the standard
/// `NSSearchToolbarItem` in a visible window's toolbar and begins a search
/// interaction, which focuses the field and selects its contents.
enum SearchToolbarFocus {
    @MainActor
    static func focusSearchField() {
        let candidateWindows = ((NSApp.keyWindow.map { [$0] } ?? []) + NSApp.orderedWindows)
            .filter(\.isVisible)

        for window in candidateWindows {
            guard let toolbar = window.toolbar else { continue }
            for case let searchItem as NSSearchToolbarItem in toolbar.items {
                window.makeKeyAndOrderFront(nil)
                searchItem.beginSearchInteraction()
                return
            }
        }
    }
}
