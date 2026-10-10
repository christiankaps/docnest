import Foundation

enum AppSplitViewLayout {
    static let sidebarWidth = 260.0
    static let inspectorWidth = 420.0
    static let documentListMinWidth = 280.0
    static let documentListIdealWidth = 740.0
    static let closedLibraryContentMinWidth = 560.0
    static let minimumClosedLibraryWindowHeight = 460.0
    static let minimumWindowHeight = 700.0
    static var defaultWindowWidth: Double { reviewDimension("DOCNEST_UI_WINDOW_WIDTH", fallback: 1480) }
    static var defaultWindowHeight: Double { reviewDimension("DOCNEST_UI_WINDOW_HEIGHT", fallback: 860) }
    static let windowContentInset = 2.0

    static var minimumOpenLibraryWindowWidth: Double {
        sidebarWidth + documentListMinWidth + inspectorWidth
    }

    static var minimumClosedLibraryWindowWidth: Double {
        closedLibraryContentMinWidth
    }

    static var minimumWindowWidth: Double {
        max(minimumOpenLibraryWindowWidth, minimumClosedLibraryWindowWidth)
    }

    private static func reviewDimension(_ key: String, fallback: Double) -> Double {
        #if DEBUG
        if let raw = ProcessInfo.processInfo.environment[key], let value = Double(raw),
           value.isFinite, value > 0 {
            return value
        }
        #endif
        return fallback
    }
}
