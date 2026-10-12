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
                Section("Pipeline") {
                    TextField("Name", text: $pipeline.name).accessibilityIdentifier("pipelineName")
                    Text("Enable the steps you need. They always run in this order: OCR → Rename → Save.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Steps") {
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $ocrEnabled) {
                            Label("OCR", systemImage: "text.viewfinder").font(.headline)
                        }.accessibilityIdentifier("enableOCR")
                        if ocrEnabled {
                            Toggle("Skip pages with existing text", isOn: $skipExistingText)
                                .accessibilityIdentifier("skipExistingText")
                            Text(skipExistingText ? "Recognize scanned pages while keeping existing searchable text." : "Recognize every page and replace existing text layers with fresh OCR.")
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        Text("Make scanned pages searchable. Annotated/form PDFs require OCR to be off.")
                            .font(.caption).foregroundStyle(.secondary)
                    }.padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $renameEnabled) {
                            Label("Rename", systemImage: "character.cursor.ibeam").font(.headline)
                        }.accessibilityIdentifier("enableRename")
                        if renameEnabled {
                            TemplateChipEditor(template: $filenameTemplate)
                        } else {
                            Text("Keep the original filename.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                    VStack(alignment: .leading, spacing: 8) {
                        Toggle(isOn: $savingEnabled) {
                            Label("Save to folder", systemImage: "folder").font(.headline)
                        }.accessibilityIdentifier("enableSave")
                            .onChange(of: savingEnabled) { _, enabled in
                                if !enabled { pipeline.unattended = false; isDefault = false }
                            }
                        if savingEnabled {
                            if let destination = pipeline.destination {
                                Text(destination.name).foregroundStyle(.secondary)
                            }
                            Button(pipeline.destination == nil ? "Choose folder…" : "Change folder…") { selectingFolder = true }
                                .buttonStyle(.borderless).accessibilityIdentifier("chooseSaveFolder")
                            Text(pipeline.unattended ? "Saves automatically after processing." : "Save to this folder after reviewing the result.")
                                .font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text("Share or save manually after processing.").font(.caption).foregroundStyle(.secondary)
                        }
                    }.padding(.vertical, 4)
                }
                Section("Execution") {
                    Toggle("Run unattended", isOn: $pipeline.unattended)
                        .disabled(!savingEnabled)
                        .onChange(of: pipeline.unattended) { _, value in if !value { isDefault = false } }
                    Toggle("Default for shared files", isOn: $isDefault).disabled(!pipeline.unattended)
                    Text("The explicit default runs automatically when you share a file to PDF Pipe. Without a default, you choose a pipeline each time. Unattended steps cannot require {text}.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("Edit pipeline").navigationBarTitleDisplayMode(.inline)
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
            .alert("Cannot save pipeline", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }.tint(PipeAppearance.accent)
    }
}
