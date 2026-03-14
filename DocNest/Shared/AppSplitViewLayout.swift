enum AppSplitViewLayout {
    static let sidebarWidth = 260.0
    static let inspectorWidth = 420.0
    static let documentListMinWidth = 280.0
    static let documentListIdealWidth = 740.0
    static let closedLibraryContentMinWidth = 360.0
    static let minimumWindowHeight = 700.0
    static let defaultWindowWidth = 1480.0
    static let defaultWindowHeight = 860.0
    static let windowContentInset = 2.0

    static var minimumOpenLibraryWindowWidth: Double {
        sidebarWidth + documentListMinWidth + inspectorWidth
    }

    static var minimumClosedLibraryWindowWidth: Double {
        sidebarWidth + closedLibraryContentMinWidth + inspectorWidth
    }

    static var minimumWindowWidth: Double {
        max(minimumOpenLibraryWindowWidth, minimumClosedLibraryWindowWidth)
    }
}