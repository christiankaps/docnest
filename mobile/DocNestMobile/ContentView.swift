import SwiftUI
import UniformTypeIdentifiers

private enum LibraryRoute: Hashable {
    case documents(LibraryFilter)
    case document(UUID)
    case recentlyDeleted
}

struct ContentView: View {
    @State private var model: LibraryModel
    @State private var selectedTab = 0
    @State private var libraryPath: [LibraryRoute] = []
    @State private var inboxPath: [LibraryRoute] = []
    @State private var importing = false
    @State private var settings = false
    @State private var managingLabels = false
    @Environment(\.scenePhase) private var scenePhase

    init(store: LibraryStore = LibraryStore()) {
        _model = State(initialValue: LibraryModel(store: store))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $libraryPath) {
                libraryContent
                    .navigationTitle("Library")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Settings", systemImage: "gearshape") { settings = true }
                        }
                        ToolbarItem(placement: .topBarTrailing) { importButton }
                    }
                    .navigationDestination(for: LibraryRoute.self, destination: destination)
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }.tag(0)
            NavigationStack(path: $inboxPath) {
                DocumentListView(model: model, inboxOnly: true)
                    .navigationTitle("Inbox")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { importButton } }
                    .navigationDestination(for: LibraryRoute.self, destination: destination)
            }
            .tabItem { Label("Inbox", systemImage: "tray") }.tag(1)
            .badge(model.inboxCount)
        }
        .task { await model.load() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active && !model.isLoading && model.loadError == nil {
                Task { await model.save { try await model.store.cleanupExpired() } }
            }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): Task { await model.importPDF(url) }
            case .failure(let error): model.actionError = error.localizedDescription
            }
        }
        .sheet(isPresented: $settings) { SettingsView() }
        .sheet(isPresented: $managingLabels) { LabelManagementView(model: model) }
        .libraryError(model)
        .alert("Already in your library", isPresented: Binding(get: { model.duplicate != nil }, set: { if !$0 { model.duplicate = nil } }), presenting: model.duplicate) { document in
            Button("Open Document") {
                selectedTab = 0
                libraryPath.append(.document(document.id))
                model.duplicate = nil
            }
            Button("Cancel", role: .cancel) { model.duplicate = nil }
        } message: { document in Text(document.filename) }
    }

    @ViewBuilder private func destination(_ route: LibraryRoute) -> some View {
        switch route {
        case .documents(let filter): DocumentListView(model: model, initialFilter: filter).navigationTitle("Documents")
        case .document(let id): DocumentView(id: id, model: model)
        case .recentlyDeleted: RecentlyDeletedView(model: model)
        }
    }

    private var importButton: some View {
        Button("Import PDF", systemImage: "square.and.arrow.down") { importing = true }
            .disabled(model.isLoading || model.isImporting || model.loadError != nil)
            .accessibilityIdentifier("importPDF")
    }

    @ViewBuilder private var libraryContent: some View {
        if model.isLoading { ProgressView("Opening library…") }
        else if let error = model.loadError { LibraryUnavailable(model: model, error: error) }
        else {
            List {
                Section {
                    NavigationLink(value: LibraryRoute.documents(LibraryFilter())) {
                        Label { LabeledContent("All Documents", value: model.documents.count.formatted()) } icon: { Image(systemName: "doc.text") }
                    }.accessibilityIdentifier("allDocuments")
                    Button { selectedTab = 1 } label: {
                        Label { LabeledContent("Inbox", value: model.inboxCount.formatted()) } icon: { Image(systemName: "tray") }
                    }.accessibilityIdentifier("inboxSummary")
                    NavigationLink(value: LibraryRoute.recentlyDeleted) {
                        Label { LabeledContent("Recently Deleted", value: model.deletedDocuments.count.formatted()) } icon: { Image(systemName: "trash") }
                    }.accessibilityIdentifier("recentlyDeleted")
                }
                if model.documents.isEmpty {
                    Section {
                        Text("Your paperwork, together").font(.headline)
                        Text("Import a PDF to keep a private copy on this iPhone.").foregroundStyle(.secondary)
                    }
                }
                Section {
                    ForEach(model.labels) { label in
                        NavigationLink(value: LibraryRoute.documents(LibraryFilter(labelIDs: [label.id]))) {
                            Label { LabeledContent(label.name, value: model.documents.filter { $0.labelIDs.contains(label.id) }.count.formatted()) } icon: { Image(systemName: "tag") }
                        }.accessibilityIdentifier("browseLabel-\(label.id)")
                    }
                } header: {
                    HStack {
                        Text("Labels")
                        Spacer()
                        Button("Manage") { managingLabels = true }.accessibilityIdentifier("manageLabels")
                    }
                }
                Section("Years") {
                    ForEach(model.years, id: \.self) { year in
                        NavigationLink(value: LibraryRoute.documents(LibraryFilter(year: year))) {
                            Text(String(year))
                        }
                    }
                    if model.years.isEmpty { Text("Years appear as you add documents.").foregroundStyle(.secondary) }
                }
            }
            .overlay(alignment: .bottom) { if model.isImporting { ProgressView("Importing PDF…").padding().background(.regularMaterial) } }
        }
    }
}

private struct DocumentListView: View {
    let model: LibraryModel
    var inboxOnly = false
    @State private var filter: LibraryFilter
    @State private var filtering = false
    @State private var selection: Set<UUID> = []
    @State private var editMode: EditMode = .inactive
    @State private var bulkLabels = false
    @State private var share: DocumentTransfer?
    @State private var preparingShare = false
    @State private var pendingTransfer: DocumentTransfer?

    init(model: LibraryModel, inboxOnly: Bool = false, initialFilter: LibraryFilter = LibraryFilter()) {
        self.model = model
        self.inboxOnly = inboxOnly
        _filter = State(initialValue: initialFilter)
    }

    private var documents: [LibraryDocument] {
        model.documents.filter { (!inboxOnly || $0.reviewState == .inbox) && filter.includes($0) }
    }

    var body: some View {
        Group {
            if model.isLoading { ProgressView("Opening library…") }
            else if let error = model.loadError { LibraryUnavailable(model: model, error: error) }
            else {
                List(selection: $selection) {
                    if !filter.labelIDs.isEmpty || filter.year != nil {
                        Section {
                            let names = model.labels.filter { filter.labelIDs.contains($0.id) }.map(\.name)
                            Text((names + (filter.year.map { [String($0)] } ?? [])).joined(separator: " · "))
                                .font(.subheadline).accessibilityIdentifier("activeFilters")
                            Button("Clear Filters") { filter = LibraryFilter() }
                        } footer: { Text("Documents must match every selected label and year.") }
                    }
                    ForEach(documents) { document in
                        NavigationLink(value: LibraryRoute.document(document.id)) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(document.title).font(.headline).lineLimit(2)
                                let names = model.labels(for: document).map(\.name)
                                if !names.isEmpty { Text(names.joined(separator: " · ")).font(.subheadline).foregroundStyle(.secondary) }
                                HStack {
                                    Text(document.documentDate.displayDate, format: .dateTime.year().month().day())
                                    if document.dateSource == .importFallback {
                                        Image(systemName: "exclamationmark.circle").accessibilityLabel("Date needs review")
                                    }
                                }.font(.subheadline).foregroundStyle(.secondary)
                            }.padding(.vertical, 3)
                        }.tag(document.id)
                        .documentActions(model: model, record: document)
                        .accessibilityIdentifier("document-\(document.id)")
                    }
                }
                .overlay {
                    if documents.isEmpty && filter == LibraryFilter() {
                        ContentUnavailableView(inboxOnly ? "Inbox is empty" : "No documents", systemImage: inboxOnly ? "tray" : "doc.text")
                    } else if documents.isEmpty {
                        ContentUnavailableView("No matching documents", systemImage: "line.3.horizontal.decrease")
                            .allowsHitTesting(false)
                    }
                }
            }
        }
        .environment(\.editMode, $editMode)
        .toolbar(editMode.isEditing ? .hidden : .automatic, for: .tabBar)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button(editMode.isEditing ? "Done" : "Select") {
                    editMode = editMode.isEditing ? .inactive : .active
                    selection = []
                }.disabled(model.isLoading || model.loadError != nil)
            }
            ToolbarItemGroup(placement: .bottomBar) {
                if editMode.isEditing {
                    Text("\(selection.count) selected in this list").font(.caption)
                    Spacer()
                    Button("Share", systemImage: "square.and.arrow.up") {
                        let ids = selection
                        preparingShare = true
                        Task {
                            defer { preparingShare = false }
                            do { share = DocumentTransfer(urls: try await model.store.exportCopies(for: ids)) }
                            catch { model.actionError = error.localizedDescription }
                        }
                    }.disabled(selection.isEmpty || preparingShare)
                    Button("Add Labels", systemImage: "tag") { bulkLabels = true }.disabled(selection.isEmpty)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("Filter", systemImage: "line.3.horizontal.decrease") { filtering = true }
                    .disabled(model.isLoading || model.loadError != nil)
            }
        }
        .sheet(isPresented: $bulkLabels) { BulkLabelsView(model: model, ids: selection) }
        .sheet(item: $share, onDismiss: {
            if let transfer = pendingTransfer { Task { for url in transfer.urls { await model.store.removeExport(url) } } }
            pendingTransfer = nil
        }) { transfer in MultiPDFShareSheet(urls: transfer.urls).onAppear { pendingTransfer = transfer } }
        .onChange(of: documents.map(\.id)) { _, ids in selection.formIntersection(Set(ids)) }
        .sheet(isPresented: $filtering) { LibraryFilterView(model: model, filter: $filter) }
        .onChange(of: model.labels) { _, labels in filter.labelIDs.formIntersection(Set(labels.map(\.id))) }
    }
}

private struct LibraryUnavailable: View {
    let model: LibraryModel
    let error: String
    var body: some View {
        ContentUnavailableView {
            Label("Library unavailable", systemImage: "exclamationmark.triangle")
        } description: { Text(error) } actions: {
            Button("Retry") { Task { await model.load() } }
        }
    }
}

private struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            Form {
                Section("Storage") {
                    Label("On this iPhone", systemImage: "iphone")
                    Text("Your library is private to DocNest. Imported PDFs are copies; sharing and exporting create separate copies.")
                        .foregroundStyle(.secondary)
                }
                Section("About") { LabeledContent("App", value: "DocNest") }
            }
            .navigationTitle("Settings")
            .toolbar { Button("Done") { dismiss() } }
        }
    }
}
