import SwiftUI

struct PipelineEditor: View {
    @ObservedObject var store: PipelineStore
    @State var pipeline: Pipeline
    @State var isDefault: Bool
    @State private var ocrEnabled: Bool
    @State private var skipExistingText: Bool
    @State private var renameEnabled: Bool
    @State private var savingEnabled: Bool
    @State private var filenameTemplate: String
    @State private var selectingFolder = false
    @State private var composingFilename = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    init(store: PipelineStore, pipeline: Pipeline, isDefault: Bool) {
        self.store = store
        _pipeline = State(initialValue: pipeline)
        _isDefault = State(initialValue: isDefault)
        _ocrEnabled = State(initialValue: pipeline.steps.contains { $0.kind == .ocr })
        _skipExistingText = State(initialValue: pipeline.steps.first { $0.kind == .ocr }?.skipExistingText ?? true)
        _renameEnabled = State(initialValue: pipeline.steps.contains { $0.kind == .rename })
        _savingEnabled = State(initialValue: pipeline.destination != nil)
        _filenameTemplate = State(initialValue: pipeline.steps.last { $0.kind == .rename }?.template ?? "{date}_{original}")
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Pipeline name", text: $pipeline.name)
                        .accessibilityIdentifier("pipelineName")
                    Text(outcomeSummary).foregroundStyle(.secondary)
                        .font(.subheadline)
                } header: { Text("Name") }
                Section {
                    Toggle(isOn: $ocrEnabled) {
                        Label("Recognize scanned pages", systemImage: "text.viewfinder")
                    }.accessibilityIdentifier("enableOCR")
                    if ocrEnabled {
                        Toggle("Keep existing searchable text", isOn: $skipExistingText)
                            .accessibilityIdentifier("skipExistingText")
                    }
                } header: { Text("1 · Recognize text") }
                  footer: {
                      if ocrEnabled { Text("Scanned pages become searchable. OCR is unavailable for annotated or form PDFs.") }
                  }
                Section {
                    Toggle(isOn: $renameEnabled) {
                        Label("Name from document", systemImage: "character.cursor.ibeam")
                    }.accessibilityIdentifier("enableRename")
                    if renameEnabled {
                        Button { composingFilename = true } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text("Filename template").foregroundStyle(.primary)
                                    Text(templateSummary).font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }.accessibilityIdentifier("editFilenameTemplate")
                    }
                } header: { Text("2 · Name file") }
                  footer: { if !renameEnabled { Text("The original filename is kept.") } }
                Section {
                    Toggle(isOn: $savingEnabled) {
                        Label("Save to folder", systemImage: "folder")
                    }.accessibilityIdentifier("enableSave")
                        .onChange(of: savingEnabled) { _, enabled in
                            if !enabled { pipeline.unattended = false; isDefault = false }
                        }
                    if savingEnabled {
                        Button { selectingFolder = true } label: {
                            HStack {
                                Text("Folder")
                                Spacer()
                                Text(pipeline.destination?.name ?? "Choose…")
                                    .foregroundStyle(.secondary).lineLimit(1)
                                Image(systemName: "chevron.right").font(.caption).foregroundStyle(.tertiary)
                            }
                        }.accessibilityIdentifier("chooseSaveFolder")
                    }
                } header: { Text("3 · Save output") }
                  footer: { Text(savingEnabled ? "The folder is used after processing." : "You can share or save the result manually.") }
                if savingEnabled {
                    Section {
                        Toggle("Run automatically", isOn: $pipeline.unattended)
                            .disabled(pipeline.destination == nil)
                            .onChange(of: pipeline.unattended) { _, value in if !value { isDefault = false } }
                        if pipeline.unattended {
                            Toggle("Default for shared files", isOn: $isDefault)
                        }
                    } header: { Text("Shared files") }
                      footer: {
                          if pipeline.destination == nil { Text("Choose a folder to enable automatic saving.") }
                          else { Text("A default pipeline processes files shared to PDF Pipe without asking you to choose one.") }
                      }
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle(store.configuration.pipelines.contains(where: { $0.id == pipeline.id }) ? "Edit Pipeline" : "New Pipeline")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do {
                            let configured = try pipeline.configured(ocr: ocrEnabled, rename: renameEnabled,
                                template: filenameTemplate, save: savingEnabled, skipExistingText: skipExistingText)
                            try store.save(configured, isDefault: isDefault)
                            dismiss()
                        } catch { self.error = error.localizedDescription }
                    }.accessibilityIdentifier("savePipeline")
                }
            }
            .sheet(isPresented: $selectingFolder) {
                FolderPicker { url in
                    do { pipeline.destination = try Destination.selected(url) }
                    catch { self.error = error.localizedDescription }
                }
            }
            .sheet(isPresented: $composingFilename) {
                NavigationStack {
                    ScrollView {
                        TemplateChipEditor(template: $filenameTemplate)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                        .background(Color(uiColor: .systemGroupedBackground))
                        .navigationTitle("Filename Template")
                        .navigationBarTitleDisplayMode(.inline)
                        .toolbar {
                            ToolbarItem(placement: .confirmationAction) {
                                Button("Done") { composingFilename = false }
                            }
                        }
                }
            }
            .alert("Cannot save pipeline", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }.tint(PipeAppearance.accent)
    }

    private var outcomeSummary: String {
        let actions = [ocrEnabled ? "Recognize text" : nil,
                       renameEnabled ? "Name file" : nil,
                       savingEnabled ? "Save to folder" : nil].compactMap { $0 }
        return actions.isEmpty ? "Keep the PDF unchanged" : actions.joined(separator: " · ")
    }

    private var templateSummary: String {
        (try? FilenameTemplate.render(filenameTemplate, values: .init(original: "Invoice",
            manualText: "Acme", processedAt: Date(), documentDate: "2026-10-05",
            words: ["Telekom", "Rechnung", "Internet"]))) ?? "Choose filename parts"
    }
}
