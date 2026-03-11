import SwiftUI
import SwiftData

struct LabelManagementView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \LabelTag.name, order: .forward) private var labels: [LabelTag]

    @State private var selectedLabelID: PersistentIdentifier?
    @State private var newLabelName = ""
    @State private var editedLabelName = ""
    @State private var errorMessage: String?

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                TextField("New label", text: $newLabelName)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addLabel)

                Button("Add", action: addLabel)
                    .disabled(newLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                Spacer()

                Button("Done") {
                    dismiss()
                }
            }
            .padding(20)

            Divider()

            HStack(spacing: 0) {
                List(labels, selection: $selectedLabelID) { label in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(label.name)
                        Text("\(label.documents.count) document\(label.documents.count == 1 ? "" : "s")")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    .tag(label.persistentModelID)
                }
                .frame(minWidth: 220)

                Divider()

                VStack(alignment: .leading, spacing: 16) {
                    if let selectedLabel {
                        Text("Edit Label")
                            .font(.headline)

                        TextField("Label name", text: $editedLabelName)
                            .textFieldStyle(.roundedBorder)
                            .onSubmit(renameSelectedLabel)

                        VStack(alignment: .leading, spacing: 8) {
                            Text("Color")
                                .font(.subheadline.weight(.medium))

                            LazyVGrid(columns: Array(repeating: GridItem(.fixed(28), spacing: 8), count: 5), spacing: 8) {
                                ForEach(LabelColor.allCases) { labelColor in
                                    Circle()
                                        .fill(labelColor.color)
                                        .frame(width: 28, height: 28)
                                        .overlay {
                                            if selectedLabel.labelColor == labelColor {
                                                Image(systemName: "checkmark")
                                                    .font(.system(size: 12, weight: .bold))
                                                    .foregroundStyle(.white)
                                            }
                                        }
                                        .onTapGesture {
                                            changeColor(of: selectedLabel, to: labelColor)
                                        }
                                }
                            }
                        }

                        HStack(spacing: 12) {
                            Button("Rename", action: renameSelectedLabel)
                                .disabled(editedLabelName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)

                            Button("Delete Label", role: .destructive) {
                                deleteSelectedLabel(selectedLabel)
                            }
                        }

                        Text("Deleting a label removes only the label assignment. Imported PDFs stay in the library.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        ContentUnavailableView(
                            "No Label Selected",
                            systemImage: "tag",
                            description: Text("Select a label to rename or delete it.")
                        )
                    }

                    Spacer()
                }
                .padding(24)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
        .frame(minWidth: 640, minHeight: 420)
        .navigationTitle("Manage Labels")
        .onAppear {
            syncSelectionIfNeeded()
        }
        .onChange(of: labels.map(\.persistentModelID)) { _, _ in
            syncSelectionIfNeeded()
        }
        .onChange(of: selectedLabelID) { _, _ in
            syncEditedName()
        }
        .alert("Label Error", isPresented: errorBinding) {
            Button("OK", role: .cancel) {
                errorMessage = nil
            }
        } message: {
            Text(errorMessage ?? "Unknown label error.")
        }
    }

    private var selectedLabel: LabelTag? {
        labels.first { $0.persistentModelID == selectedLabelID }
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

    private func syncSelectionIfNeeded() {
        let validIDs = Set(labels.map(\.persistentModelID))

        if let selectedLabelID, !validIDs.contains(selectedLabelID) {
            self.selectedLabelID = nil
        }

        if self.selectedLabelID == nil {
            self.selectedLabelID = labels.first?.persistentModelID
        }

        syncEditedName()
    }

    private func syncEditedName() {
        editedLabelName = selectedLabel?.name ?? ""
    }

    private func addLabel() {
        do {
            let label = try ManageLabelsUseCase.createLabel(named: newLabelName, using: modelContext)
            selectedLabelID = label.persistentModelID
            newLabelName = ""
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func renameSelectedLabel() {
        guard let selectedLabel else {
            return
        }

        do {
            let renamedLabel = try ManageLabelsUseCase.rename(selectedLabel, to: editedLabelName, using: modelContext)
            selectedLabelID = renamedLabel.persistentModelID
            editedLabelName = renamedLabel.name
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func changeColor(of label: LabelTag, to color: LabelColor) {
        label.labelColor = color
        do {
            try modelContext.save()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func deleteSelectedLabel(_ label: LabelTag) {
        do {
            try ManageLabelsUseCase.delete(label, using: modelContext)
            selectedLabelID = labels.first { $0.persistentModelID != label.persistentModelID }?.persistentModelID
        } catch {
            errorMessage = error.localizedDescription
        }
    }
}

#Preview {
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try! ModelContainer(for: DocumentRecord.self, LabelTag.self, configurations: config)

    let labels = LabelTag.makeSamples()
    container.mainContext.insert(labels.finance)
    container.mainContext.insert(labels.tax)
    container.mainContext.insert(labels.contracts)

    return LabelManagementView()
        .modelContainer(container)
}