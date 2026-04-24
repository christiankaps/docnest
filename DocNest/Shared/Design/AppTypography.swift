import SwiftUI

enum AppTypography {
    static let windowTitle = Font.title3.weight(.semibold)
    static let columnHeader = Font.caption.weight(.semibold)
    static let listTitle = Font.body.weight(.medium)
    static let listMeta = Font.subheadline
    static let labelChip = Font.caption.weight(.medium)
    static let title = Font.title2.weight(.semibold)
    static let titleLarge = Font.title.weight(.semibold)
    static let sectionTitle = Font.headline
    static let sectionLabel = Font.subheadline.weight(.semibold)
    static let body = Font.body
    static let caption = Font.caption
    static let captionStrong = Font.caption.weight(.semibold)
    static let sidebarSection = Font.system(size: 12, weight: .semibold)
    static let settingsTitle = Font.title3.weight(.semibold)
    static let settingsSubtitle = Font.callout
}

enum AppTheme {
    static let windowBackground = Color(nsColor: .windowBackgroundColor)
    static let panelBackground = Color(nsColor: .controlBackgroundColor)
    static let contentBackground = Color(nsColor: .textBackgroundColor)
    static let headerBackground = Color(nsColor: .windowBackgroundColor).opacity(0.96)
    static let separator = Color.primary.opacity(0.07)
    static let subtleSeparator = Color.primary.opacity(0.045)
    static let quietFill = Color.primary.opacity(0.035)
    static let quietHoverFill = Color.primary.opacity(0.055)
    static let selectedFill = Color.accentColor.opacity(0.13)
    static let selectedStroke = Color.accentColor.opacity(0.62)
    static let secondaryText = Color.secondary.opacity(0.82)
}
