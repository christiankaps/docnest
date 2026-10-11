import SwiftUI

struct PipelineEditor: View {
    @ObservedObject var store: PipelineStore
    @State var pipeline: Pipeline
    @State var isDefault: Bool
    @State private var selectingFolder = false
    @State private var error: String?
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Pipeline") {
                    TextField("Name", text: $pipeline.name).accessibilityIdentifier("pipelineName")
                    Text("Steps run from top to bottom. Saving is always last.").font(.footnote).foregroundStyle(.secondary)
                }
                Section("Steps") {
                    ForEach($pipeline.steps) { $step in
                        VStack(alignment: .leading, spacing: 8) {
                            Label(step.title, systemImage: step.kind == .ocr ? "text.viewfinder" : "character.cursor.ibeam").font(.headline)
                            if step.kind == .rename {
                                TextField("Filename template", text: $step.template)
                                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                                    .accessibilityIdentifier("filenameTemplate")
                                Text("{original} · {date} · {text}\nDate uses yyyy-MM-dd. The .pdf extension is added automatically.")
                                    .font(.caption).foregroundStyle(.secondary)
                                if let preview = try? FilenameTemplate.render(step.template, original: "Invoice", text: "Acme", date: Date()) {
                                    Text("Example: \(preview)").font(.caption).foregroundStyle(.teal)
                                }
                            } else {
                                Text("Recognize text on pages without existing text. Language detection is automatic. Annotated/form PDFs require a pipeline without OCR.")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                        }.padding(.vertical, 4)
                    }.onDelete { pipeline.steps.remove(atOffsets: $0) }
                     .onMove { pipeline.steps.move(fromOffsets: $0, toOffset: $1) }
                    Menu {
                        ForEach(PipelineStep.Kind.allCases, id: \.self) { kind in
                            Button(kind == .ocr ? "OCR" : "Rename") { pipeline.steps.append(.init(kind: kind)) }
                        }
                    } label: { Label("Add step", systemImage: "plus") }
                    EditButton()
                }
                Section("Destination") {
                    if let destination = pipeline.destination {
                        Label(destination.name, systemImage: "folder")
                        Button("Remove destination", role: .destructive) {
                            pipeline.destination = nil
                            pipeline.unattended = false
                            isDefault = false
                        }
                    }
                    Button(pipeline.destination == nil ? "Choose folder…" : "Change folder…") { selectingFolder = true }
                    Text("A configured folder is optional for reviewed results and required for unattended saving. Existing files are never overwritten.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Execution") {
                    Toggle("Run unattended", isOn: $pipeline.unattended)
                        .onChange(of: pipeline.unattended) { _, value in if !value { isDefault = false } }
                    Toggle("Default for shared files", isOn: $isDefault).disabled(!pipeline.unattended)
                    Text("The explicit default runs automatically when you share a file to PdfPipe. Without a default, you choose a pipeline each time. Unattended steps cannot require {text}.")
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Edit pipeline").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        do { try store.save(pipeline, isDefault: isDefault); dismiss() }
                        catch { self.error = error.localizedDescription }
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
        }.tint(.teal)
    }
}
