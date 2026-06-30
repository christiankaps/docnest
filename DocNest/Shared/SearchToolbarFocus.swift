import AppKit

/// Bridges the ⌘F "Find" command to the native `.searchable` toolbar field.
///
/// macOS 14 has no SwiftUI API to programmatically focus a `.searchable`
/// field (`searchFocused(_:)` is macOS 15+), so this locates the standard
/// `NSSearchToolbarItem` in the key window's toolbar and begins a search
/// interaction, which focuses the field and selects its contents.
enum SearchToolbarFocus {
    @MainActor
    static func focusSearchField() {
        guard let toolbar = NSApp.keyWindow?.toolbar else { return }
        for case let searchItem as NSSearchToolbarItem in toolbar.items {
            searchItem.beginSearchInteraction()
            return
        }
    }
}
