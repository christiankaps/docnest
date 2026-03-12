import SwiftUI
import SwiftData

enum LibrarySection: String, CaseIterable, Identifiable {
    case allDocuments = "All Documents"
    case recent = "Recent Imports"
    case needsLabels = "Needs Labels"

    var id: String { rawValue }
}

struct LibrarySidebarView: View {
    @Binding var selectedSection: LibrarySection
    let labels: [LabelTag]
    @Binding var selectedLabelIDs: Set<PersistentIdentifier>
    @Environment(\.modelContext) private var modelContext

    @State private var isAddingLabel = false
    @State private var newLabelName = ""
    @State private var newLabelColor: LabelColor = .blue
    @State private var editingLabelID: PersistentIdentifier?
    @State private var editedLabelName = ""
    @State private var errorMessage: String?
    @State private var labelSelectionState = SidebarLabelSelectionState<PersistentIdentifier>()
    @State private var pendingSelectionPropagationTask: Task<Void, Never>?

    private var sortedLabels: [LabelTag] {
        labels.sorted {
            if $0.sortOrder == $1.sortOrder {
                return $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
            }
            return $0.sortOrder < $1.sortOrder
        }
    }

    var body: some View {
        List {
            Section("Library") {
                ForEach(LibrarySection.allCases) { section in
                    Button {
                        selectedSection = section
                        if section == .needsLabels {
                            labelSelectionState.clear()
                            propagateDisplayedSelection()
                        }
                    } label: {
                        HStack {
                            Label(section.rawValue, systemImage: iconName(for: section))
                            Spacer()
                            if selectedSection == section {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.tint)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Label Filters") {
                HStack {
                    Button("Clear Label Filters") {
                        labelSelectionState.clear()
                        propagateDisplayedSelection()
                    }
                    .disabled(labelSelectionState.displayedSelection.isEmpty)

                    Spacer()

                    Button {
                        isAddingLabel = true
                    } label: {
                        Image(systemName: "plus")
                    }
                    .buttonStyle(.plain)
                    .help("Add Label")
                }

                if isAddingLabel {
                    VStack(spacing: 8) {
                        HStack(spacing: 8) {
                            TextField("New label", text: $newLabelName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit(addLabel)

                            Menu {
                                ForEach(LabelColor.allCases) { color in
                                    Button {
                                        newLabelColor = color
                                    } label: {
                                        HStack(spacing: 8) {
                                            Circle()
                                                .fill(color.color)
                                                .frame(width: 16, height: 16)
                                                .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                            Text(color.displayName)
                                            if newLabelColor == color {
                                                Image(systemName: "checkmark")
                                            }
                                        }
                                    }
                                }
                            } label: {
                                HStack(spacing: 8) {
                                    Circle()
                                        .fill(newLabelColor.color)
                                        .frame(width: 16, height: 16)
                                        .overlay(Circle().stroke(Color.secondary.opacity(0.3), lineWidth: 1))
                                    Text(newLabelColor.displayName)
                                        .font(AppTypography.caption)
                                }
                                .foregroundStyle(.primary)
                            }
                            .help("Choose label color")

                            Button("Add", action: addLabel)
                                .disabled(newLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                        }
                    }
                }

                if labels.isEmpty {
                    Text("No labels yet")
                        .font(AppTypography.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(sortedLabels) { label in
                        if editingLabelID == label.persistentModelID {
                            TextField("Label name", text: $editedLabelName)
                                .textFieldStyle(.roundedBorder)
                                .onSubmit {
                                    renameLabel(label)
                                }
                        } else {
                            Button {
                                toggleLabelSelection(label)
                            } label: {
                                HStack {
                                    Circle()
                                        .fill(label.labelColor.color)
                                        .frame(width: 10, height: 10)
                                    Text(label.name)
                                    Spacer()
                                    if labelSelectionState.displayedSelection.contains(label.persistentModelID) {
                                        Image(systemName: "checkmark.circle.fill")
                                            .foregroundStyle(.tint)
                                    }
                                }
                            }
                            .buttonStyle(.plain)
                            .contextMenu {
                                Button("Rename") {
                                    beginEditing(label)
                                }

                                Menu("Color") {
                                    ForEach(LabelColor.allCases) { color in
                                        Button {
                                            changeColor(of: label, to: color)
                                        } label: {
                                            HStack {
                                                Text(color.displayName)
                                                if label.labelColor == color {
                                                    Image(systemName: "checkmark")
                                                }
                                            }
                                        }
                                    }
                                }

                                Button("Delete", role: .destructive) {
                                    deleteLabel(label)
                                }
                            }
                            .onTapGesture(count: 2) {
                                beginEditing(label)
                            }
                        }
                    }
                    .onMove(perform: moveLabels)
                }
            }
        }
        .navigationTitle("Library")
        .alert("Label Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown label error.")
        }
        .onAppear {
            labelSelectionState.replaceDisplayedSelection(with: selectedLabelIDs)
        }
        .onChange(of: selectedLabelIDs) { _, newSelection in
            labelSelectionState.replaceDisplayedSelection(with: newSelection)
        }
        .onChange(of: labels.map(\.persistentModelID)) { _, labelIDs in
            labelSelectionState.syncAvailableSelections(Set(labelIDs))
        }
        .onDisappear {
            pendingSelectionPropagationTask?.cancel()
        }
    }

    private var errorBinding: Binding<Bool> {
        Binding(
            get: { errorMessage != nil },
            set: { newValue in
                if !newValue {
                    errorMessage = nil
                }
            }
        )
    }

    private func toggleLabelSelection(_ label: LabelTag) {
        labelSelectionState.toggle(label.persistentModelID)
        propagateDisplayedSelection()
    }

    private func addLabel() {
        do {
            _ = try ManageLabelsUseCase.createLabel(named: newLabelName, color: newLabelColor, using: modelContext)
            newLabelName = ""
            newLabelColor = .blue
            isAddingLabel = false
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func beginEditing(_ label: LabelTag) {
        editingLabelID = label.persistentModelID
        editedLabelName = label.name
    }

    private func renameLabel(_ label: LabelTag) {
        do {
            _ = try ManageLabelsUseCase.rename(label, to: editedLabelName, using: modelContext)
            editingLabelID = nil
            editedLabelName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeColor(of label: LabelTag, to color: LabelColor) {
        do {
            try ManageLabelsUseCase.changeColor(of: label, to: color, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteLabel(_ label: LabelTag) {
        do {
            try ManageLabelsUseCase.delete(label, using: modelContext)
            labelSelectionState.syncAvailableSelections(Set(labels.map(\.persistentModelID)))
            propagateDisplayedSelection()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func moveLabels(from source: IndexSet, to destination: Int) {
        do {
            try ManageLabelsUseCase.reorderLabels(from: source, to: destination, labels: sortedLabels, using: modelContext)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func iconName(for section: LibrarySection) -> String {
        switch section {
        case .allDocuments:
            "doc.richtext"
        case .recent:
            "clock"
        case .needsLabels:
            "tag.slash"
        }
    }

    private func propagateDisplayedSelection() {
        pendingSelectionPropagationTask?.cancel()

        let displayedSelection = labelSelectionState.displayedSelection
        pendingSelectionPropagationTask = Task { @MainActor in
            await Task.yield()

            guard !Task.isCancelled else {
                return
            }

            selectedLabelIDs = displayedSelection
        }
    }
}

#Preview {
    let labels = LabelTag.makeSamples()
    LibrarySidebarView(
        selectedSection: .constant(.allDocuments),
        labels: [labels.finance, labels.tax, labels.contracts],
        selectedLabelIDs: .constant([])
    )
}