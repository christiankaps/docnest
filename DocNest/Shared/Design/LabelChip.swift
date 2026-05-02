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
                    .fill(Color.primary.opacity(0.08))
                    .frame(width: 1)
                    .padding(.vertical, verticalPadding + 2)
                    .accessibilityHidden(true)

                valueSegment(text: valueSegmentText)
            }
        }
        .background(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(chipFill)
        )
        .overlay(
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .strokeBorder(chipStroke, lineWidth: 1)
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
            } else {
                Circle()
                    .fill(color.color)
                    .frame(width: markerSize, height: markerSize)
                    .accessibilityHidden(true)
            }
            Text(name)
                .font(chipFont)
                .foregroundStyle(Color.primary.opacity(0.82))
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
        .foregroundStyle(valueForeground)
        .padding(.horizontal, valueHorizontalPadding)
        .padding(.vertical, max(verticalPadding - 1, 2))
        .background(
            RoundedRectangle(cornerRadius: max(cornerRadius - 2, 4), style: .continuous)
                .fill(valueFill)
        )
        .padding(.horizontal, 3)
        .padding(.vertical, 2)

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

    private var markerSize: CGFloat {
        switch size {
        case .compact: 6
        case .regular: 7
        }
    }

    private var chipFill: Color {
        color.color.opacity(valueSegmentText == nil ? 0.12 : 0.10)
    }

    private var chipStroke: Color {
        color.color.opacity(0.18)
    }

    private var valueFill: Color {
        if valueText == nil {
            return Color.primary.opacity(0.045)
        }
        return color.color.opacity(0.18)
    }

    private var valueForeground: Color {
        if valueText == nil {
            return Color.secondary.opacity(0.88)
        }
        return Color.primary.opacity(0.86)
    }
}
