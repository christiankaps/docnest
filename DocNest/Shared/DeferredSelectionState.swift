struct DeferredSelectionState<ID: Hashable> {
    private(set) var visualSelection: Set<ID> = []
    private(set) var appliedSelection: Set<ID> = []

    mutating func replaceVisualSelection(with newSelection: Set<ID>) {
        visualSelection = newSelection
    }

    mutating func toggleVisualSelection(for id: ID) {
        if visualSelection.contains(id) {
            visualSelection.remove(id)
        } else {
            visualSelection.insert(id)
        }
    }

    mutating func commitVisualSelection() {
        appliedSelection = visualSelection
    }

    mutating func syncAvailableSelections(_ availableSelection: Set<ID>) {
        visualSelection.formIntersection(availableSelection)
        appliedSelection.formIntersection(availableSelection)
    }
}