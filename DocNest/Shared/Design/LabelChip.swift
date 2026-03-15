import SwiftUI

struct LabelChip: View {
    let name: String
    let color: LabelColor
    var icon: String? = nil
    var size: Size = .regular

    enum Size {
        case compact
        case regular
    }

    var body: some View {
        HStack(spacing: 3) {
            if let icon, !icon.isEmpty {
                Text(icon)
                    .font(chipFont)
            }
            Text(name)
                .font(chipFont)
                .foregroundStyle(color.color)
        }
        .padding(.horizontal, horizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(Capsule().fill(color.color.opacity(0.16)))
    }

    private var chipFont: Font {
        switch size {
        case .compact: AppTypography.labelChip
        case .regular: AppTypography.captionStrong
        }
    }

    private var horizontalPadding: CGFloat {
        switch size {
        case .compact: 8
        case .regular: 10
        }
    }

    private var verticalPadding: CGFloat {
        switch size {
        case .compact: 3
        case .regular: 6
        }
    }
}
