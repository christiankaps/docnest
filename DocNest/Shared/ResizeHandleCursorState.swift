enum ResizeHandleCursorUpdate: Equatable {
    case none
    case resizeLeftRight
    case arrow
}

struct ResizeHandleCursorState {
    private(set) var isHovering = false
    private(set) var isCursorActive = false

    mutating func hoverChanged(_ isHovering: Bool) -> ResizeHandleCursorUpdate {
        guard self.isHovering != isHovering else {
            return .none
        }

        self.isHovering = isHovering
        return isHovering ? activateCursor() : deactivateCursor()
    }

    mutating func dragEnded() -> ResizeHandleCursorUpdate {
        guard !isHovering else {
            return .none
        }

        return deactivateCursor()
    }

    mutating func disappeared() -> ResizeHandleCursorUpdate {
        isHovering = false
        return deactivateCursor()
    }

    private mutating func activateCursor() -> ResizeHandleCursorUpdate {
        guard !isCursorActive else {
            return .none
        }

        isCursorActive = true
        return .resizeLeftRight
    }

    private mutating func deactivateCursor() -> ResizeHandleCursorUpdate {
        guard isCursorActive else {
            return .none
        }

        isCursorActive = false
        return .arrow
    }
}