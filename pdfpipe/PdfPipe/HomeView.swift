import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var store: PipelineStore
    @State private var editing: Pipeline?
    @State private var importing = false
    @State private var choosingPipeline = false
    @State private var importPipelineID: UUID?
    @State private var session: DocumentSessionModel?
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            List {
                if let storeError = store.error {
                    Section {
                        Label(storeError, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                        Button("Retry loading configuration") { store.reload() }
                    }
                }
                Section {
                    if store.configuration.pipelines.isEmpty {
                        ContentUnavailableView {
                            Label("No pipelines yet", systemImage: "arrow.trianglehead.branch")
                        } description: {
                            Text("Create a pipeline to process your first document.")
                        } actions: {
                            Button("Create pipeline") { editing = Pipeline() }
                                .buttonStyle(.borderedProminent)
                                .disabled(store.error != nil)
                        }
                        .listRowBackground(Color.clear)
                    } else {
                        ForEach(store.configuration.pipelines) { pipeline in
                            Button { editing = pipeline } label: {
                                VStack(alignment: .leading, spacing: 5) {
                                    HStack {
                                        Text(pipeline.name).font(.body.weight(.semibold)).foregroundStyle(.primary)
                                        Spacer()
                                        if store.configuration.defaultID == pipeline.id {
                                            Label("Default for sharing", systemImage: "checkmark.circle.fill")
                                                .font(.caption).foregroundStyle(.secondary)
                                        }
                                    }
                                    Text(pipeline.summary.isEmpty ? "Keep PDF unchanged" : pipeline.summary)
                                        .font(.subheadline).foregroundStyle(.secondary).lineLimit(2)
                                    if pipeline.unattended && store.configuration.defaultID != pipeline.id {
                                        Text("Runs automatically when selected")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                }.padding(.vertical, 3)
                            }.buttonStyle(.plain)
                             .accessibilityIdentifier("pipeline-\(pipeline.id)")
                             .swipeActions(edge: .trailing) {
                                 Button("Delete", systemImage: "trash", role: .destructive) { perform { try store.delete(pipeline) } }
                             }
                             .contextMenu {
                                 Button("Duplicate", systemImage: "plus.square.on.square") { perform { try store.duplicate(pipeline) } }
                                 Button("Delete", systemImage: "trash", role: .destructive) { perform { try store.delete(pipeline) } }
                             }
                        }
                    }
                }
            }
            .listStyle(.insetGrouped)
            .navigationTitle("Pipelines")
            .toolbar {
                #if DEBUG
                if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                    ToolbarItem(placement: .topBarLeading) {
                        Button("Test document") { openFixture() }.accessibilityIdentifier("openFixture")
                    }
                }
                #endif
                ToolbarItem(placement: .primaryAction) {
                    Button { editing = Pipeline() } label: { Image(systemName: "plus") }
                        .accessibilityLabel("New pipeline")
                        .accessibilityIdentifier("newPipeline")
                        .disabled(store.error != nil)
                }
            }
            .safeAreaInset(edge: .bottom) {
                if !store.configuration.pipelines.isEmpty {
                    Button {
                        importPipelineID = nil
                        choosingPipeline = true
                    } label: {
                        Label("Import a document", systemImage: "square.and.arrow.down")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("importDocument")
                    .disabled(store.error != nil)
                    .padding(.horizontal).padding(.vertical, 10)
                    .background(.bar)
                }
            }
            .sheet(isPresented: $choosingPipeline, onDismiss: {
                if importPipelineID != nil { importing = true }
            }) {
                NavigationStack {
                    List {
                        if store.configuration.pipelines.isEmpty {
                            ContentUnavailableView("Create a pipeline first", systemImage: "arrow.trianglehead.branch",
                                description: Text("Add a pipeline on the home screen, then import a document."))
                        }
                        ForEach(store.configuration.pipelines) { pipeline in
                            Button {
                                importPipelineID = pipeline.id
                                choosingPipeline = false
                            } label: {
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(pipeline.name).font(.headline)
                                    Text(pipeline.summary.isEmpty ? "Keep PDF unchanged" : pipeline.summary)
                                        .font(.subheadline).foregroundStyle(.secondary)
                                }
                            }.accessibilityIdentifier("importPipeline-\(pipeline.id)")
                        }
                    }
                    .navigationTitle("Choose a pipeline")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("Cancel") { choosingPipeline = false }
                        }
                    }
                }
            }
            .sheet(item: $editing) { pipeline in
                PipelineEditor(store: store, pipeline: pipeline, isDefault: store.configuration.defaultID == pipeline.id)
            }
            .sheet(isPresented: Binding(get: { session != nil }, set: { _ in })) {
                if let session { WorkbenchView(model: session, store: store) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .jpeg, .png]) { result in
                switch result {
                case .success(let url): open(url, autoRun: false, pipelineID: importPipelineID)
                case .failure(let error):
                    let failure = error as NSError
                    if failure.domain != NSCocoaErrorDomain || failure.code != NSUserCancelledError {
                        self.error = error.localizedDescription
                    }
                }
                importPipelineID = nil
            }
            .onOpenURL { url in
                if session != nil {
                    perform { try InboxDelivery.discard(url) }
                    if error == nil { error = "Finish or discard the current document before opening another." }
                }
                else { open(url, autoRun: true) }
            }
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { store.reload() }
                if phase == .background { perform { try InboxDelivery.removeUnclaimed() } }
            }
            .task {
                do {
                    try InboxDelivery.excludeFromBackup()
                    try TemporarySession.removeAbandoned(root: TemporarySession.root())
                }
                catch { self.error = error.localizedDescription }
            }
            .alert("PDF Pipe", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }.tint(PipeAppearance.accent)
    }

    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }

    private func open(_ url: URL, autoRun: Bool, pipelineID: UUID? = nil) {
        let model = DocumentSessionModel()
        model.pipelineID = pipelineID
        model.onFinished = { session = nil }
        session = model
        model.importFile(url, store: store, autoRun: autoRun)
    }

    #if DEBUG
    private func openFixture() {
        do { open(try DevelopmentFixtures.document(), autoRun: false) }
        catch { self.error = error.localizedDescription }
    }
    #endif
}
