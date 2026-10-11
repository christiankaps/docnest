import SwiftUI

struct DocumentTransfer: Identifiable {
    let id = UUID()
    let urls: [URL]
}

struct MultiPDFShareSheet: UIViewControllerRepresentable {
    let urls: [URL]
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: urls, applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

extension View {
    func documentActions(model: LibraryModel, record: LibraryDocument) -> some View {
        modifier(DocumentActions(model: model, record: record))
    }
}

private struct DocumentActions: ViewModifier {
    let model: LibraryModel
    let record: LibraryDocument
    @State private var labels = false
    @State private var rename = false
    @State private var deleting = false
    @State private var transfer: DocumentTransfer?
    @State private var copies: [URL] = []
    @State private var preparing = false

    func body(content: Content) -> some View {
        content
            .swipeActions {
                Button("Delete", role: .destructive) { deleting = true }
                Button("Labels") { labels = true }.tint(.blue)
            }
            .contextMenu {
                Button("Share", systemImage: "square.and.arrow.up") {
                    preparing = true
                    Task {
                        defer { preparing = false }
                        do {
                            copies = try await model.store.exportCopies(for: [record.id])
                            transfer = DocumentTransfer(urls: copies)
                        } catch { model.actionError = error.localizedDescription }
                    }
                }.disabled(preparing)
                Button("Rename", systemImage: "pencil") { rename = true }
                Button("Labels", systemImage: "tag") { labels = true }
                Button("Delete", systemImage: "trash", role: .destructive) { deleting = true }
            }
            .confirmationDialog("Delete Document?", isPresented: $deleting, titleVisibility: .visible) {
                Button("Delete", role: .destructive) { Task { await model.save { try await model.store.deleteDocument(record.id) } } }
            } message: { Text("Recover this document from Recently Deleted for 30 days.") }
            .sheet(isPresented: $labels) { DocumentLabelsView(model: model, record: record) }
            .sheet(isPresented: $rename) { RenameDocumentView(model: model, record: record) }
            .sheet(item: $transfer, onDismiss: {
                let exported = copies
                copies = []
                Task { for url in exported { await model.store.removeExport(url) } }
            }) { MultiPDFShareSheet(urls: $0.urls) }
    }
}

struct RenameDocumentView: View {
    let model: LibraryModel
    let record: LibraryDocument
    @State private var name: String
    @Environment(\.dismiss) private var dismiss
    init(model: LibraryModel, record: LibraryDocument) {
        self.model = model
        self.record = record
        _name = State(initialValue: record.filename)
    }
    var body: some View {
        NavigationStack {
            Form {
                TextField("Filename", text: $name).autocorrectionDisabled()
                Text("If this name is already used, a numbered suffix will be added.").foregroundStyle(.secondary)
            }
            .navigationTitle("Rename Document")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await model.save({ try await model.store.renameDocument(record.id, name: name) }) { dismiss() } }
                    }.disabled(model.isSaving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .interactiveDismissDisabled(model.isSaving)
            .libraryError(model)
        }
    }
}

struct BulkLabelsView: View {
    let model: LibraryModel
    let ids: Set<UUID>
    @State private var selected: Set<UUID> = []
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(model.labels) { label in
                        LabelSelectionRow(name: label.name, selected: Binding(get: { selected.contains(label.id) }, set: { checked in
                            if checked { selected.insert(label.id) } else { selected.remove(label.id) }
                        }))
                    }
                } footer: { Text("Add labels to \(ids.count) selected documents. Existing labels stay assigned.") }
            }
            .environment(\.editMode, .constant(.inactive))
            .navigationTitle("Add Labels")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        Task { if await model.save({ try await model.store.addLabels(selected, to: ids) }) { dismiss() } }
                    }.disabled(model.isSaving || selected.isEmpty)
                }
            }
            .interactiveDismissDisabled(model.isSaving)
            .libraryError(model)
        }
    }
}

struct RecentlyDeletedView: View {
    let model: LibraryModel
    var body: some View {
        List {
            Section {
                ForEach(model.deletedDocuments) { record in
                    VStack(alignment: .leading) {
                        Text(record.title).font(.headline)
                        if let date = record.deletedAt { Text("Deleted \(date.formatted(date: .abbreviated, time: .omitted))").font(.caption).foregroundStyle(.secondary) }
                        Button("Recover") { Task { await model.save { try await model.store.recover(record.id) } } }.disabled(model.isSaving)
                    }
                }
            } footer: { Text("Documents are kept for 30 days. Expired documents are removed when DocNest can run.") }
        }
        .navigationTitle("Recently Deleted")
        .overlay { if model.deletedDocuments.isEmpty { ContentUnavailableView("No deleted documents", systemImage: "trash").allowsHitTesting(false) } }
    }
}
