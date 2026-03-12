struct SidebarLabelSelectionState<ID: Hashable> {
    private(set) var displayedSelection: Set<ID> = []

    mutating func replaceDisplayedSelection(with newSelection: Set<ID>) {
        displayedSelection = newSelection
    }

    mutating func toggle(_ id: ID) {
        if displayedSelection.contains(id) {
            displayedSelection.remove(id)
        } else {
            displayedSelection.insert(id)
        }
    }

    mutating func clear() {
        displayedSelection.removeAll()
    }

    mutating func syncAvailableSelections(_ availableSelection: Set<ID>) {
        displayedSelection.formIntersection(availableSelection)
    }
}