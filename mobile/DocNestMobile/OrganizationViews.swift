import SwiftUI

extension View {
    func libraryError(_ model: LibraryModel) -> some View {
        alert("Couldn’t complete action", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) { model.actionError = nil }
        } message: { Text(model.actionError ?? "") }
    }
}

struct LibraryFilterView: View {
    let model: LibraryModel
    @Binding var filter: LibraryFilter
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.labels) { label in
                        LabelSelectionRow(name: label.name, selected: Binding(get: { filter.labelIDs.contains(label.id) }, set: { selected in
                            if selected { filter.labelIDs.insert(label.id) } else { filter.labelIDs.remove(label.id) }
                        }))
                    }
                } header: { Text("Labels") } footer: { Text("Documents must match every selected label and year.") }
                Section("Year") {
                    Picker("Year", selection: $filter.year) {
                        Text("All Years").tag(nil as Int?)
                        ForEach(Set(model.years + (filter.year.map { [$0] } ?? [])).sorted(by: >), id: \.self) { year in
                            Text(String(year)).tag(Optional(year))
                        }
                    }.pickerStyle(.inline).labelsHidden()
                }
                Button("Clear Filters") { filter = LibraryFilter() }
            }
            .navigationTitle("Filter")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}

struct LabelManagementView: View {
    let model: LibraryModel
    @State private var editor: LabelEditRequest?
    @State private var deleting: LibraryLabel?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List(model.labels) { label in
                Button { editor = LabelEditRequest(label: label) } label: {
                    Label(label.name, systemImage: "tag").foregroundStyle(.primary)
                }
                .swipeActions {
                    Button("Delete", role: .destructive) { deleting = label }
                }
                .contextMenu {
                    Button("Rename", systemImage: "pencil") { editor = LabelEditRequest(label: label) }
                    Button("Delete Label", systemImage: "trash", role: .destructive) { deleting = label }
                }
            }
            .navigationTitle("Manage Labels")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItem(placement: .primaryAction) {
                    Button("New Label", systemImage: "plus") { editor = LabelEditRequest() }
                }
            }
            .confirmationDialog("Delete Label?", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { label in
                Button("Delete Label", role: .destructive) {
                    Task { await model.save { try await model.store.deleteLabel(label.id) } }
                }
                Button("Cancel", role: .cancel) { }
            } message: { label in
                Text("Remove “\(label.name)” from all documents? Your documents will stay in the library.")
            }
            .sheet(item: $editor) { LabelNameView(model: model, label: $0.label) }
            .libraryError(model)
            .disabled(model.isSaving)
        }
    }
}

private struct LabelEditRequest: Identifiable {
    let id = UUID()
    var label: LibraryLabel?
}

private struct LabelNameView: View {
    let model: LibraryModel
    let label: LibraryLabel?
    @State private var name: String
    @FocusState private var focused: Bool
    @Environment(\.dismiss) private var dismiss

    init(model: LibraryModel, label: LibraryLabel?) {
        self.model = model
        self.label = label
        _name = State(initialValue: label?.name ?? "")
    }

    var body: some View {
        NavigationStack {
            Form { TextField("Label name", text: $name).focused($focused).submitLabel(.done).onSubmit { save() } }
                .navigationTitle(label == nil ? "New Label" : "Rename Label")
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button("Save", action: save).disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || model.isSaving) }
                }
                .interactiveDismissDisabled(model.isSaving)
                .libraryError(model)
                .task { focused = true }
        }
    }

    private func save() {
        Task {
            let saved = await model.save {
                if let label { try await model.store.renameLabel(label.id, name: name) }
                else { try await model.store.createLabel(name: name) }
            }
            if saved { dismiss() }
        }
    }
}

struct DocumentLabelsView: View {
    let model: LibraryModel
    let id: UUID
    @State private var selected: Set<UUID>
    @State private var newLabel = false
    @Environment(\.dismiss) private var dismiss

    init(model: LibraryModel, record: LibraryDocument) {
        self.model = model
        id = record.id
        _selected = State(initialValue: record.labelIDs)
    }

    var body: some View {
        NavigationStack {
            List {
                ForEach(model.labels) { label in
                    LabelSelectionRow(name: label.name, selected: Binding(get: { selected.contains(label.id) }, set: { checked in
                        if checked { selected.insert(label.id) } else { selected.remove(label.id) }
                    }))
                }
                Button("New Label", systemImage: "plus") { newLabel = true }
            }
            .navigationTitle("Labels")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.save({ try await model.store.updateDocument(id, labels: selected) }) { dismiss() }
                        }
                    }.disabled(model.isSaving)
                }
            }
            .sheet(isPresented: $newLabel) { LabelNameView(model: model, label: nil) }
            .interactiveDismissDisabled(model.isSaving)
            .libraryError(model)
        }
    }
}

struct DocumentDateView: View {
    let model: LibraryModel
    let id: UUID
    @State private var date: Date
    @Environment(\.dismiss) private var dismiss

    init(model: LibraryModel, record: LibraryDocument) {
        self.model = model
        id = record.id
        _date = State(initialValue: record.documentDate.displayDate)
    }

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Document date", selection: $date, displayedComponents: .date).datePickerStyle(.wheel)
                    .environment(\.calendar, Calendar(identifier: .gregorian))
                Text("Choose the date on the document. Saving confirms this date; the filename stays the same.")
                    .foregroundStyle(.secondary)
            }
            .navigationTitle("Document Date")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task {
                            if await model.save({ try await model.store.updateDocument(id, manualDate: DocumentDate(date)) }) { dismiss() }
                        }
                    }.disabled(model.isSaving)
                }
            }
            .interactiveDismissDisabled(model.isSaving)
            .libraryError(model)
        }
    }
}

struct LabelSelectionRow: View {
    let name: String
    @Binding var selected: Bool
    var body: some View {
        Button { selected.toggle() } label: {
            HStack {
                Text(name).foregroundStyle(.primary)
                Spacer()
                if selected { Image(systemName: "checkmark").fontWeight(.semibold) }
            }.contentShape(Rectangle())
        }
        .accessibilityLabel(name)
        .accessibilityValue(selected ? String(localized: "Selected") : String(localized: "Not selected"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}
