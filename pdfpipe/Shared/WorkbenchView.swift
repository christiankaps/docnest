import SwiftUI

struct WorkbenchView: View {
    @ObservedObject var model: DocumentSessionModel
    @ObservedObject var store: PipelineStore
    @State private var shareURL: URL?
    @State private var exportURL: URL?
    @State private var exportedName: String?
    @State private var preparingExport = false

    private var selected: Pipeline? { store.configuration.pipelines.first { $0.id == model.pipelineID } }

    var body: some View {
        NavigationStack {
            Group {
                if let saved = model.savedName {
                    ContentUnavailableView {
                        Label("Finished", systemImage: "checkmark.circle.fill")
                    } description: {
                        Text("\(saved)\nThe temporary copy has been removed.")
                    } actions: { Button("Done") { model.discard() }.buttonStyle(.borderedProminent) }
                } else {
                    ScrollView {
                        VStack(alignment: .leading, spacing: 20) {
                            if let document = model.document {
                                PDFPreview(url: document.url)
                                    .frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 18))
                                    .accessibilityLabel("Document preview")
                                attributes(document.facts)
                                if !model.processed { pipelineSelection }
                                if model.processed { resultActions(document) }
                            }
                            if model.busy {
                                VStack(spacing: 12) {
                                    ProgressView(model.progress).frame(maxWidth: .infinity)
                                    Button("Cancel processing", role: .cancel) { model.cancelProcessing() }
                                }.padding()
                            }
                            if model.document == nil && !model.busy {
                                ContentUnavailableView("No document available", systemImage: "doc", description: Text("Discard this session and import a supported file again."))
                            }
                        }.padding(20)
                    }
                }
            }
            .navigationTitle("Document")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    if model.savedName == nil { Button("Discard", role: .destructive) { model.discard() }.disabled(preparingExport) }
                }
            }
            .interactiveDismissDisabled()
            .alert("PDF Pipe", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) {
                Button("OK") { model.error = nil }
            } message: { Text(model.error ?? "") }
            .sheet(isPresented: Binding(get: { shareURL != nil }, set: { if !$0 { shareURL = nil } }), onDismiss: finishExport) {
                if let shareURL { SharePicker(url: shareURL) { completed, error in
                    if let error { model.error = error }
                    if completed { exportedName = shareURL.lastPathComponent }
                } }
            }
            .sheet(isPresented: Binding(get: { exportURL != nil }, set: { if !$0 { exportURL = nil } }), onDismiss: finishExport) {
                if let exportURL { ExportPicker(url: exportURL) { completed, name in
                    if completed { exportedName = name ?? exportURL.lastPathComponent }
                } }
            }
        }
        .tint(.teal)
    }

    private func attributes(_ facts: DocumentFacts) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(facts.filename).font(.headline).textSelection(.enabled)
            HStack {
                Label("\(facts.pages) \(facts.pages == 1 ? "page" : "pages")", systemImage: "doc.on.doc")
                Spacer()
                Text(ByteCountFormatter.string(fromByteCount: facts.bytes, countStyle: .file))
            }
            Text("Source: \(facts.sourceFormat) · \(facts.dimensions)")
            Label(facts.hasText ? "Text available" : "No text detected", systemImage: facts.hasText ? "text.magnifyingglass" : "doc.viewfinder")
        }.font(.subheadline).foregroundStyle(.secondary)
    }

    private var pipelineSelection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Choose a pipeline").font(.title3.bold())
            if store.configuration.pipelines.isEmpty {
                Text("Create a pipeline in the PDF Pipe app, then share or import this file again.").foregroundStyle(.secondary)
            } else {
                Picker("Pipeline", selection: $model.pipelineID) {
                    Text("Select…").tag(nil as UUID?)
                    ForEach(store.configuration.pipelines) { Text($0.name).tag(Optional($0.id)) }
                }.pickerStyle(.menu).accessibilityIdentifier("pipelinePicker")
                if let selected {
                    let preview = model.filenamePreview(selected)
                    Text(selected.summary.isEmpty ? "Keep PDF unchanged" : selected.summary).font(.subheadline).foregroundStyle(.secondary)
                    if selected.needsText {
                        TextField("Text for {text}", text: $model.manualText).textFieldStyle(.roundedBorder)
                    }
                    switch preview {
                    case .success(let filename):
                        Text("Filename: \(filename)").font(.subheadline).textSelection(.enabled)
                            .accessibilityIdentifier("proposedFilename")
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.red)
                    }
                    if selected.unattended { Label("Saves automatically to \(selected.destination?.name ?? "folder")", systemImage: "folder.badge.gearshape").font(.footnote) }
                    Button("Run pipeline") { model.run(selected) }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                        .frame(maxWidth: .infinity).disabled(model.busy || (try? preview.get()) == nil)
                        .accessibilityIdentifier("runPipeline")
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
         .padding().background(.thinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .disabled(model.busy)
    }

    private func resultActions(_ document: ProcessedDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Ready to export").font(.title3.bold())
            ForEach(Array(document.report.enumerated()), id: \.offset) { _, value in
                Label(value, systemImage: "checkmark").font(.subheadline)
            }
            TextField("Filename", text: $model.filename).textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("resultFilename")
            HStack {
                Button { prepareExport(share: true) } label: { Label("Share", systemImage: "square.and.arrow.up") }
                Button { prepareExport(share: false) } label: { Label("Save to Files", systemImage: "folder") }
            }.buttonStyle(.bordered).disabled(model.busy || preparingExport)
            if let destination = selected?.destination {
                Button("Save to \(destination.name)") { model.save(destination) }
                    .buttonStyle(.borderedProminent).disabled(model.busy || preparingExport)
            }
        }
    }

    private func prepareExport(share: Bool) {
        preparingExport = true
        Task {
            defer { preparingExport = false }
            do {
                try await model.applyFilename()
                if let url = model.document?.url {
                    if share { shareURL = url } else { exportURL = url }
                }
            } catch { model.error = error.localizedDescription }
        }
    }

    private func finishExport() {
        if let exportedName { model.exported(exportedName); self.exportedName = nil }
    }
}
