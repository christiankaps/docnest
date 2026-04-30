import SwiftUI

struct LabelChip: View {
    let name: String
    let color: LabelColor
    var icon: String? = nil
    var size: Size = .regular
    var valueText: String? = nil
    var showsMissingValueAffordance = false
    var showsValueEditIndicator = false
    var onNameTap: (() -> Void)? = nil
    var onValueTap: (() -> Void)? = nil

    enum Size {
        case compact
        case regular
    }

    var body: some View {
        HStack(spacing: 0) {
            nameSegment

            if let valueSegmentText {
                Rectangle()
                    .fill(color.color.opacity(0.24))
                    .frame(width: 1)
                    .padding(.vertical, verticalPadding + 1)
                    .accessibilityHidden(true)

                valueSegment(text: valueSegmentText)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(color.color.opacity(0.16))
        )
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityDescription)
    }

    @ViewBuilder
    private var nameSegment: some View {
        let content = HStack(spacing: 3) {
            if let icon, !icon.isEmpty {
                Text(icon)
                    .font(chipFont)
                    .accessibilityHidden(true)
            }
            Text(name)
                .font(chipFont)
                .foregroundStyle(color.color)
                .lineLimit(1)
        }
        .padding(.leading, horizontalPadding)
        .padding(.trailing, valueSegmentText == nil ? horizontalPadding : 7)
        .padding(.vertical, verticalPadding)

        if let onNameTap {
            Button(action: onNameTap) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(name) label")
        } else {
            content
        }
    }

    @ViewBuilder
    private func valueSegment(text: String) -> some View {
        let content = HStack(spacing: 3) {
            Text(text)
                .font(chipFont.monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            if showsValueEditIndicator {
                Image(systemName: "pencil")
                    .font(.system(size: editIndicatorSize, weight: .semibold))
                    .accessibilityHidden(true)
            }
        }
        .foregroundStyle(valueText == nil ? Color.secondary : Color.primary)
        .padding(.horizontal, valueHorizontalPadding)
        .padding(.vertical, verticalPadding)
        .background(color.color.opacity(valueText == nil ? 0.06 : 0.1))

        if let onValueTap {
            Button(action: onValueTap) {
                content
            }
            .buttonStyle(.plain)
            .accessibilityLabel(valueText == nil ? "Add \(name) value" : "Edit \(name) value, \(text)")
        } else {
            content
        }
    }

    private var valueSegmentText: String? {
        if let valueText {
            return valueText
        }
        if showsMissingValueAffordance {
            return "+ value"
        }
        return nil
    }

    private var accessibilityDescription: String {
        if let valueText {
            return "\(name) label, value \(valueText)"
        }
        if showsMissingValueAffordance {
            return "\(name) label, no value"
        }
        return "\(name) label"
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

    private var valueHorizontalPadding: CGFloat {
        switch size {
        case .compact: 7
        case .regular: 9
        }
    }

    private var cornerRadius: CGFloat {
        switch size {
        case .compact: 6
        case .regular: 7
        }
    }

    private var editIndicatorSize: CGFloat {
        switch size {
        case .compact: 8
        case .regular: 10
        }
    }
}
