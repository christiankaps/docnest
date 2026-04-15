import SwiftUI
import SwiftData

struct QuickLabelPickerView: View {
    @Environment(LibraryCoordinator.self) private var coordinator
    @Binding var isPresented: Bool

    @State private var searchText = ""
    @State private var highlightedIndex = 0
    @State private var preparedAssignmentCounts: [PersistentIdentifier: Int] = [:]
    @State private var preparedDisplayItems: [DisplayItem] = []
    @FocusState private var isSearchFieldFocused: Bool

    // MARK: - Derived Data

    private var selectedDocuments: [DocumentRecord] {
        coordinator.selectedDocuments
    }

    private var allLabels: [LabelTag] {
        coordinator.allLabels
    }

    private var allGroups: [LabelGroup] {
        coordinator.allLabelGroups
    }

    private var displayItems: [DisplayItem] {
        preparedDisplayItems
    }

    /// Only selectable (label) items, for keyboard navigation.
    private var selectableIndices: [Int] {
        displayItems.enumerated().compactMap { index, item in
            if case .label = item { return index } else { return nil }
        }
    }

    private func assignmentState(for label: LabelTag) -> LabelAssignmentState {
        guard !selectedDocuments.isEmpty else { return .none }
        let assignedCount = selectedAssignmentCounts[label.persistentModelID, default: 0]
        if assignedCount == selectedDocuments.count { return .all }
        if assignedCount > 0 { return .partial }
        return .none
    }

    private var selectedAssignmentCounts: [PersistentIdentifier: Int] {
        preparedAssignmentCounts
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            searchField
            Divider()
            labelList
        }
        .frame(width: 320)
        .frame(maxHeight: 400)
        .fixedSize(horizontal: false, vertical: true)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.2), radius: 16, y: 8)
        .onAppear {
            refreshPreparedState()
            highlightedIndex = selectableIndices.first ?? 0
            isSearchFieldFocused = true
        }
        .onChange(of: searchText) {
            refreshPreparedState()
            highlightedIndex = selectableIndices.first ?? 0
        }
        .onChange(of: coordinator.selectedDocumentIDs) {
            refreshPreparedState()
            highlightedIndex = selectableIndices.first ?? 0
        }
        .onChange(of: coordinator.allLabels.count) {
            refreshPreparedState()
            highlightedIndex = selectableIndices.first ?? 0
        }
        .onChange(of: coordinator.allLabelGroups.count) {
            refreshPreparedState()
            highlightedIndex = selectableIndices.first ?? 0
        }
        .onKeyPress(.upArrow) {
            moveHighlight(-1)
            return .handled
        }
        .onKeyPress(.downArrow) {
            moveHighlight(1)
            return .handled
        }
        .onKeyPress(.return) {
            toggleHighlightedLabel()
            return .handled
        }
        .onKeyPress(.escape) {
            isPresented = false
            return .handled
        }
    }

    // MARK: - Subviews

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(.secondary)
                .font(.system(size: 14))
            TextField("Filter labels\u{2026}", text: $searchText)
                .textFieldStyle(.plain)
                .font(AppTypography.body)
                .focused($isSearchFieldFocused)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
    }

    private var labelList: some View {
        Group {
            if displayItems.isEmpty {
                Text(searchText.isEmpty ? "No labels available" : "No matching labels")
                    .font(AppTypography.body)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 0) {
                            ForEach(Array(displayItems.enumerated()), id: \.offset) { index, item in
                                switch item {
                                case .groupHeader(let group):
                                    groupHeaderRow(group)
                                case .label(let label):
                                    labelRow(label, isHighlighted: index == highlightedIndex)
                                        .id(index)
                                        .contentShape(Rectangle())
                                        .onTapGesture {
                                            coordinator.toggleLabel(label, on: selectedDocuments)
                                            refreshPreparedState()
                                        }
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onChange(of: highlightedIndex) { _, newIndex in
                        withAnimation(.easeOut(duration: 0.1)) {
                            proxy.scrollTo(newIndex, anchor: .center)
                        }
                    }
                }
            }
        }
    }

    private func groupHeaderRow(_ group: LabelGroup) -> some View {
        Text(group.name)
            .font(AppTypography.caption)
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 12)
            .padding(.top, 10)
            .padding(.bottom, 4)
    }

    private func labelRow(_ label: LabelTag, isHighlighted: Bool) -> some View {
        HStack(spacing: 8) {
            if let icon = label.icon, !icon.isEmpty {
                Text(icon)
                    .font(AppTypography.body)
            } else {
                Circle()
                    .fill(label.labelColor.color)
                    .frame(width: 10, height: 10)
            }

            Text(label.name)
                .font(AppTypography.body)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer()

            switch assignmentState(for: label) {
            case .all:
                Image(systemName: "checkmark")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
            case .partial:
                Image(systemName: "minus")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
            case .none:
                EmptyView()
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            RoundedRectangle(cornerRadius: 6)
                .fill(isHighlighted ? Color.accentColor.opacity(0.15) : Color.clear)
                .padding(.horizontal, 4)
        )
    }

    // MARK: - Keyboard Navigation

    private func moveHighlight(_ direction: Int) {
        let indices = selectableIndices
        guard !indices.isEmpty else { return }

        guard let currentPos = indices.firstIndex(of: highlightedIndex) else {
            highlightedIndex = indices.first ?? 0
            return
        }

        let newPos = currentPos + direction
        if newPos >= 0 && newPos < indices.count {
            highlightedIndex = indices[newPos]
        }
    }

    private func toggleHighlightedLabel() {
        guard case .label(let label) = displayItems[safe: highlightedIndex] else { return }
        coordinator.toggleLabel(label, on: selectedDocuments)
        refreshPreparedState()
    }

    private func refreshPreparedState() {
        preparedAssignmentCounts = selectedDocuments.reduce(into: [:]) { counts, document in
            for label in document.labels {
                counts[label.persistentModelID, default: 0] += 1
            }
        }

        if !searchText.isEmpty {
            let query = searchText
            preparedDisplayItems = Array(allLabels.lazy
                .filter { $0.name.localizedCaseInsensitiveContains(query) }
                .map(DisplayItem.label))
            return
        }

        let groupedLabels = Dictionary(grouping: allLabels, by: \.groupID)
        var items = groupedLabels[nil, default: []].map(DisplayItem.label)

        let sortedGroups = allGroups.sorted {
            $0.sortOrder != $1.sortOrder
                ? $0.sortOrder < $1.sortOrder
                : $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }

        for group in sortedGroups {
            let groupLabels = groupedLabels[group.id, default: []]
            guard !groupLabels.isEmpty else { continue }
            items.append(.groupHeader(group))
            items.append(contentsOf: groupLabels.map(DisplayItem.label))
        }

        preparedDisplayItems = items
    }
}

// MARK: - Supporting Types

private enum DisplayItem {
    case groupHeader(LabelGroup)
    case label(LabelTag)
}

enum LabelAssignmentState {
    case none, partial, all
}

private extension Array {
    subscript(safe index: Int) -> Element? {
        indices.contains(index) ? self[index] : nil
    }
}
