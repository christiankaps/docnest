import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @State private var model: LibraryModel
    @State private var selectedTab = 0
    @State private var libraryPath: [LibraryDocument] = []
    @State private var inboxPath: [LibraryDocument] = []
    @State private var importing = false
    @State private var settings = false

    init(store: LibraryStore = LibraryStore()) {
        _model = State(initialValue: LibraryModel(store: store))
    }

    var body: some View {
        TabView(selection: $selectedTab) {
            NavigationStack(path: $libraryPath) {
                documentList(inboxOnly: false)
                    .navigationTitle("Library")
                    .toolbar {
                        ToolbarItem(placement: .topBarLeading) {
                            Button("Settings", systemImage: "gearshape") { settings = true }
                        }
                        ToolbarItem(placement: .topBarTrailing) { importButton }
                    }
            }
            .tabItem { Label("Library", systemImage: "books.vertical") }.tag(0)
            NavigationStack(path: $inboxPath) {
                documentList(inboxOnly: true)
                    .navigationTitle("Inbox")
                    .toolbar { ToolbarItem(placement: .topBarTrailing) { importButton } }
            }
            .tabItem { Label("Inbox", systemImage: "tray") }.tag(1)
            .badge(model.documents.filter { $0.reviewState == .inbox }.count)
        }
        .task { await model.load() }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf]) { result in
            switch result {
            case .success(let url): Task { await model.importPDF(url) }
            case .failure(let error): model.actionError = error.localizedDescription
            }
        }
        .sheet(isPresented: $settings) { SettingsView() }
        .alert("Couldn’t import PDF", isPresented: Binding(get: { model.actionError != nil }, set: { if !$0 { model.actionError = nil } })) {
            Button("OK", role: .cancel) { model.actionError = nil }
        } message: { Text(model.actionError ?? "") }
        .alert("Already in your library", isPresented: Binding(get: { model.duplicate != nil }, set: { if !$0 { model.duplicate = nil } }), presenting: model.duplicate) { document in
            Button("Open Document") {
                selectedTab = 0
                libraryPath.append(document)
                model.duplicate = nil
            }
            Button("Cancel", role: .cancel) { model.duplicate = nil }
        } message: { document in Text(document.filename) }
    }

    private var importButton: some View {
        Button("Import PDF", systemImage: "square.and.arrow.down") { importing = true }
            .disabled(model.isLoading || model.isImporting || model.loadError != nil)
            .accessibilityIdentifier("importPDF")
    }

    @ViewBuilder private func documentList(inboxOnly: Bool) -> some View {
        Group {
            if model.isLoading {
                ProgressView("Opening library…")
            } else if let error = model.loadError {
                ContentUnavailableView {
                    Label("Library unavailable", systemImage: "exclamationmark.triangle")
                } description: { Text(error) } actions: {
                    Button("Retry") { Task { await model.load() } }
                }
            } else {
                let documents = model.documents.filter { !inboxOnly || $0.reviewState == .inbox }
                if documents.isEmpty {
                    ContentUnavailableView {
                        Label(inboxOnly ? "Inbox is empty" : "Your paperwork, together", systemImage: inboxOnly ? "tray" : "doc.text")
                    } description: {
                        Text("Import a PDF to keep a private copy on this iPhone.")
                    } actions: { importButton }
                } else {
                    List(documents) { document in
                        NavigationLink(value: document) {
                            VStack(alignment: .leading, spacing: 5) {
                                Text(document.title).font(.headline).lineLimit(2)
                                HStack {
                                    Text(document.documentDate.displayDate, format: .dateTime.year().month().day())
                                    Image(systemName: "exclamationmark.circle")
                                        .accessibilityLabel("Date needs review")
                                }
                                .font(.subheadline).foregroundStyle(.secondary)
                            }
                            .padding(.vertical, 3)
                        }
                    }
                }
            }
        }
        .safeAreaInset(edge: .bottom) {
            if model.isImporting {
                HStack { ProgressView(); Text("Importing PDF…") }
                    .padding().frame(maxWidth: .infinity).background(.regularMaterial)
            }
        }
        .navigationDestination(for: LibraryDocument.self) { document in
            DocumentView(record: document, store: model.store)
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
