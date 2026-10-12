import SwiftUI

struct WorkbenchView: View {
    @ObservedObject var model: DocumentSessionModel
    @ObservedObject var store: PipelineStore
    @State private var shareURL: URL?
    @State private var exportURL: URL?
    @State private var exportedName: String?
    @State private var preparingExport = false
    @State private var showingDetails = false
    @ScaledMetric(relativeTo: .body) private var cloudBaseSize: CGFloat = 15

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
                        VStack(alignment: .leading, spacing: 18) {
                            if let document = model.document {
                                if model.processed {
                                    PDFPreview(url: document.url)
                                        .frame(height: 200)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .accessibilityLabel("Processed document preview")
                                    resultActions(document)
                                } else if model.awaitingNaming {
                                    namingSelection
                                } else {
                                    Text(document.facts.filename)
                                        .font(.headline)
                                        .lineLimit(2)
                                        .textSelection(.enabled)
                                    PDFPreview(url: document.url)
                                        .frame(height: 220)
                                        .clipShape(RoundedRectangle(cornerRadius: 12))
                                        .accessibilityLabel("Document preview")
                                    DisclosureGroup("Document details", isExpanded: $showingDetails) {
                                        attributes(document.facts)
                                    }
                                    if !model.busy { pipelineSelection }
                                }
                            }
                            if model.busy {
                                VStack(alignment: .leading, spacing: 12) {
                                    ProgressView(model.progress)
                                    Button("Cancel processing", role: .cancel) { model.cancelProcessing() }
                                }.frame(maxWidth: .infinity, alignment: .leading)
                            }
                            if model.document == nil && !model.busy {
                                ContentUnavailableView("No document available", systemImage: "doc", description: Text("Discard this session and import a supported file again."))
                            }
                        }.padding()
                    }
                }
            }
            .navigationTitle(model.savedName != nil ? "Finished" : model.processed ? "Result" :
                model.awaitingNaming ? "Choose Filename" : model.busy ? "Processing" : "Review Document")
            .navigationBarTitleDisplayMode(.inline)
            .safeAreaInset(edge: .bottom) {
                if model.savedName == nil && !model.busy {
                    if model.awaitingNaming {
                        let preview = model.selectedFilenamePreview()
                        primaryAction("Continue", identifier: "confirmFilename",
                            disabled: (try? preview.get()) == nil) { model.confirmNaming() }
                    } else if !model.processed, let selected {
                        let preview = model.filenamePreview(selected)
                        primaryAction("Run Pipeline", identifier: "runPipeline",
                            disabled: (try? preview.get()) == nil) { model.run(selected) }
                    } else if model.processed {
                        if let destination = selected?.destination {
                            primaryAction("Save to \(destination.name)", identifier: "saveToFolder",
                                disabled: preparingExport) { model.save(destination) }
                        } else {
                            primaryAction("Share PDF", identifier: "sharePDF",
                                disabled: preparingExport) { prepareExport(share: true) }
                        }
                    }
                }
            }
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
        .tint(PipeAppearance.accent)
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
        VStack(alignment: .leading, spacing: 10) {
            Text("Pipeline").font(.headline)
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
                        TextField("Text for filename", text: $model.manualText).textFieldStyle(.roundedBorder)
                    }
                    switch preview {
                    case .success(let filename):
                        Text("Filename: \(filename)").font(.subheadline).textSelection(.enabled)
                            .accessibilityIdentifier("proposedFilename")
                    case .failure(let error):
                        Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                            .font(.footnote).foregroundStyle(.red)
                    }
                    if selected.unattended { Label("Saves automatically to \(selected.destination?.name ?? "folder")", systemImage: "folder").font(.footnote) }
                }
            }
        }.frame(maxWidth: .infinity, alignment: .leading)
        .disabled(model.busy)
    }

    private var namingSelection: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let analysis = model.analysis {
                switch analysis.date {
                case .found(let value):
                    Label("Document date: \(value)", systemImage: "calendar")
                case .fallback:
                    Label("No document date found. Using processing date.", systemImage: "calendar.badge.clock")
                case .ambiguous(let candidates):
                    Text("Several dates are plausible. Choose the document date.")
                        .foregroundStyle(.orange)
                    Picker("Document date", selection: $model.selectedDate) {
                        Text("Choose a date").tag(nil as String?)
                        ForEach(candidates, id: \.self) { candidate in
                            Text(candidate).tag(Optional(candidate))
                        }
                    }.accessibilityIdentifier("documentDatePicker")
                }
                Text("Suggested words").font(.headline)
                if analysis.words.isEmpty {
                    Text("No significant words found. Enter a word to name this document.")
                        .foregroundStyle(.secondary)
                } else {
                    let highest = max(analysis.words.first?.score ?? 1, 1)
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 110), spacing: 8)], alignment: .leading, spacing: 8) {
                        ForEach(analysis.words) { word in
                            let selected = model.selectedWords.contains(word.text)
                            Button {
                                model.toggleWord(word.text)
                            } label: {
                                HStack(spacing: 4) {
                                    if selected { Image(systemName: "checkmark") }
                                    Text(word.text).lineLimit(2)
                                }
                                .font(.system(size: cloudBaseSize + 2 + 3 * word.score / highest,
                                              weight: selected || word.score / highest > 0.7 ? .semibold : .regular))
                                .frame(maxWidth: .infinity, minHeight: 38)
                                .padding(.horizontal, 8)
                                .background(selected ? PipeAppearance.accent.opacity(0.15) : Color.secondary.opacity(0.08),
                                    in: Capsule())
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("\(word.text), \(selected ? "selected" : "not selected")")
                            .accessibilityIdentifier("cloud-\(word.id)")
                        }
                    }
                }
                HStack {
                    TextField("Add a word", text: $model.manualKeyword)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("manualKeyword")
                    Button("Add") { model.addManualKeyword() }
                        .disabled(model.manualKeyword.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
                if !model.selectedWords.isEmpty {
                    Text("Selected: \(model.selectedWords.joined(separator: ", "))")
                        .font(.subheadline).foregroundStyle(.secondary)
                } else {
                    Text("Without a selection, the template uses the highest-ranked words automatically.")
                        .font(.caption).foregroundStyle(.secondary)
                }
                let preview = model.selectedFilenamePreview()
                switch preview {
                case .success(let value):
                    Text("Filename: \(value)").textSelection(.enabled)
                        .accessibilityIdentifier("proposedFilename")
                case .failure(let error):
                    Label(error.localizedDescription, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                }
                Button("Change pipeline") { model.resetNaming() }
                    .disabled(model.busy)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func resultActions(_ document: SessionDocument) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Label("Ready to export", systemImage: "checkmark.circle.fill").font(.title3.bold())
            ForEach(Array(document.report.enumerated()), id: \.offset) { _, value in
                Label(value, systemImage: "checkmark").font(.subheadline)
            }
            TextField("Filename", text: $model.filename).textFieldStyle(.roundedBorder)
                .textInputAutocapitalization(.never).autocorrectionDisabled()
                .accessibilityIdentifier("resultFilename")
            if selected?.destination != nil {
                Button { prepareExport(share: true) } label: { Label("Share PDF", systemImage: "square.and.arrow.up") }
                    .disabled(model.busy || preparingExport)
            }
            Button { prepareExport(share: false) } label: { Label("Save to Files", systemImage: "folder") }
                .disabled(model.busy || preparingExport)
        }
    }

    private func primaryAction(_ title: String, identifier: String, disabled: Bool,
                               action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).frame(maxWidth: .infinity) }
            .buttonStyle(.borderedProminent).controlSize(.large)
            .disabled(disabled).accessibilityIdentifier(identifier)
            .padding(.horizontal).padding(.vertical, 10)
            .background(.bar)
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
