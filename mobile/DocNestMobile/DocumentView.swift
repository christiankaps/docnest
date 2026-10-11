import PDFKit
import SwiftUI
import UniformTypeIdentifiers

struct DocumentView: View {
    let id: UUID
    let model: LibraryModel
    private var store: LibraryStore { model.store }
    @State private var pdf: PDFDocument?
    @State private var openError: String?
    @State private var actionError: String?
    @State private var showDetails = false
    @State private var showLabels = false
    @State private var showSearch = false
    @State private var query = ""
    @State private var completedQuery: String?
    @FocusState private var searchFocused: Bool
    @State private var hits: [PDFSearchHit] = []
    @State private var selectedHit: PDFSearchHit?
    @State private var searching = false
    @State private var transfer: Transfer?
    @State private var showExporter = false
    @State private var exportURL: URL?
    @State private var preparingCopy = false

    private struct Transfer: Identifiable {
        let id = UUID()
        let url: URL
    }

    var body: some View {
        if let record = model.document(id) { documentBody(record) }
        else { ContentUnavailableView("Document unavailable", systemImage: "doc.badge.ellipsis") }
    }

    private func documentBody(_ record: LibraryDocument) -> some View {
        VStack(spacing: 0) {
            if showSearch {
                HStack {
                    TextField("Search this PDF", text: $query).textFieldStyle(.roundedBorder)
                        .focused($searchFocused).autocorrectionDisabled().onSubmit { search() }
                    Button("Find") { search() }.disabled(query.isEmpty || searching)
                }.padding()
                if searching { ProgressView("Searching…") }
                if completedQuery == query && !query.isEmpty && !searching && hits.isEmpty { Text("No matches").font(.caption).foregroundStyle(.secondary) }
                if !hits.isEmpty {
                    ScrollView(.horizontal) {
                        HStack {
                            ForEach(hits) { hit in
                                Button {
                                    selectedHit = hit
                                } label: {
                                    VStack(alignment: .leading) {
                                        Text("Page \(hit.pageIndex + 1)").font(.caption.bold())
                                        Text(hit.snippet).font(.caption).lineLimit(2).frame(maxWidth: 200, alignment: .leading)
                                    }.padding(8)
                                }.buttonStyle(.bordered)
                            }
                        }.padding(.horizontal)
                    }.frame(maxHeight: 95)
                }
            }
            if let pdf {
                PDFCanvas(document: pdf, hit: selectedHit).accessibilityIdentifier("pdfCanvas")
            } else if let openError {
                ContentUnavailableView("Couldn’t open PDF", systemImage: "doc.badge.ellipsis", description: Text(openError))
            } else { ProgressView("Opening PDF…").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .navigationTitle(record.title).navigationBarTitleDisplayMode(.inline)
        .toolbar(.hidden, for: .tabBar)
        .toolbar {
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Share", systemImage: "square.and.arrow.up") { prepareCopy(export: false) }
                    .disabled(preparingCopy || pdf == nil).accessibilityIdentifier("sharePDF")
                Spacer()
                Button("Labels", systemImage: "tag") { showLabels = true }.accessibilityIdentifier("documentLabels")
                Spacer()
                Button("Search", systemImage: "magnifyingglass") { showSearch.toggle() }
                    .disabled(pdf == nil).accessibilityIdentifier("searchPDF")
                Spacer()
                Button("Details", systemImage: "info.circle") { showDetails = true }.accessibilityIdentifier("documentDetails")
            }
            ToolbarItem(placement: .topBarTrailing) {
                if record.reviewState == .inbox {
                    Button("Done") { Task { await model.save { try await store.updateDocument(id, reviewed: true) } } }
                        .disabled(model.isSaving).accessibilityIdentifier("finishReview")
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu("More", systemImage: "ellipsis") {
                    Button("Export PDF", systemImage: "folder") { prepareCopy(export: true) }.disabled(preparingCopy || pdf == nil)
                }
            }
        }
        .task {
            do {
                let url = try await store.originalURL(for: record.id)
                guard let loaded = PDFDocument(url: url) else { throw LibraryError.invalidPDF }
                pdf = loaded
            } catch { openError = error.localizedDescription }
        }
        .onChange(of: query) { _, _ in hits = []; selectedHit = nil; completedQuery = nil }
        .sheet(isPresented: $showDetails) { DocumentDetails(id: id, model: model) }
        .sheet(isPresented: $showLabels) { DocumentLabelsView(model: model, record: record) }
        .libraryError(model)
        .sheet(item: $transfer, onDismiss: cleanupExport) { item in
            ShareSheet(url: item.url)
        }
        .fileExporter(isPresented: $showExporter, item: exportURL.map(PDFExport.init), contentTypes: [.pdf], defaultFilename: record.filename) { result in
            if case .failure(let error) = result { actionError = error.localizedDescription }
            cleanupExport()
        } onCancellation: { cleanupExport() }
        .alert("Couldn’t complete action", isPresented: Binding(get: { actionError != nil }, set: { if !$0 { actionError = nil } })) {
            Button("OK", role: .cancel) { actionError = nil }
        } message: { Text(actionError ?? "") }
        .overlay { if preparingCopy { ProgressView("Preparing copy…").padding().background(.regularMaterial, in: RoundedRectangle(cornerRadius: 12)) } }
    }

    private func search() {
        let requested = query
        searchFocused = false
        searching = true
        Task {
            do {
                let results = try await store.search(document: id, text: requested)
                if query == requested { hits = results; selectedHit = results.first; completedQuery = requested }
            } catch { actionError = error.localizedDescription }
            searching = false
        }
    }

    private func prepareCopy(export: Bool) {
        preparingCopy = true
        Task {
            defer { preparingCopy = false }
            do {
                let url = try await store.exportCopy(for: id)
                exportURL = url
                if export { showExporter = true }
                else { transfer = Transfer(url: url) }
            } catch { actionError = error.localizedDescription }
        }
    }

    private func cleanupExport() {
        if let url = exportURL { Task { await store.removeExport(url) } }
        exportURL = nil
    }
}

private struct DocumentDetails: View {
    let id: UUID
    let model: LibraryModel
    @State private var editingDate = false
    @State private var editingLabels = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            if let record = model.document(id) {
                Form {
                    Section("Document") {
                        LabeledContent("Filename", value: record.filename)
                        LabeledContent("Document date", value: record.documentDate.displayDate.formatted(date: .abbreviated, time: .omitted))
                            .accessibilityIdentifier("documentDateValue")
                        if record.dateSource == .importFallback {
                            Label("Date needs review", systemImage: "exclamationmark.circle")
                            Text("Using the import date until the document date is reviewed.").foregroundStyle(.secondary)
                        }
                        Button("Edit Date") { editingDate = true }
                        LabeledContent("Pages", value: record.pageCount.formatted())
                        LabeledContent("Size", value: ByteCountFormatter.string(fromByteCount: record.byteCount, countStyle: .file))
                    }
                    Section("Labels") {
                        ForEach(model.labels(for: record)) { Text($0.name) }
                        Button("Edit Labels") { editingLabels = true }
                    }
                    Section("Import") {
                        LabeledContent("Imported", value: record.importedAt.formatted(date: .abbreviated, time: .shortened))
                        LabeledContent("Review", value: record.reviewState == .inbox ? String(localized: "In Inbox") : String(localized: "Reviewed"))
                    }
                }
                .navigationTitle("Details")
                .toolbar { Button("Done") { dismiss() } }
                .sheet(isPresented: $editingDate) { DocumentDateView(model: model, record: record) }
                .sheet(isPresented: $editingLabels) { DocumentLabelsView(model: model, record: record) }
            }
        }
    }
}

private struct PDFCanvas: UIViewRepresentable {
    let document: PDFDocument
    let hit: PDFSearchHit?

    func makeUIView(context: Context) -> PDFView {
        let view = PDFView()
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.document = document
        return view
    }

    func updateUIView(_ view: PDFView, context: Context) {
        if view.document !== document { view.document = document }
        if hit == nil { view.clearSelection(); context.coordinator.selected = nil }
        if let hit, context.coordinator.selected != hit.id,
           let page = document.page(at: hit.pageIndex), let selection = page.selection(for: hit.range) {
            view.setCurrentSelection(selection, animate: true)
            view.go(to: selection)
            context.coordinator.selected = hit.id
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }
    final class Coordinator { var selected: UUID? }
}

private struct ShareSheet: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: [url], applicationActivities: nil)
    }
    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private struct PDFExport: Transferable {
    let url: URL
    static var transferRepresentation: some TransferRepresentation {
        FileRepresentation(exportedContentType: .pdf) { item in
            SentTransferredFile(item.url)
        }
        .suggestedFileName { $0.url.lastPathComponent }
    }
}
