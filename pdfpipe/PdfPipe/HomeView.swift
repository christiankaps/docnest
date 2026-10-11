import SwiftUI
import UniformTypeIdentifiers

struct HomeView: View {
    @ObservedObject var store: PipelineStore
    @State private var editing: Pipeline?
    @State private var importing = false
    @State private var session: DocumentSessionModel?
    @State private var error: String?
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 18) {
                        Image("BrandIcon").resizable().frame(width: 76, height: 76)
                            .clipShape(RoundedRectangle(cornerRadius: 18)).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text("PDFs, ready to go.").font(.title2.bold())
                            Text("Process a copy. Keep the original.").font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                    Button { importing = true } label: {
                        Label("Import a document", systemImage: "square.and.arrow.down").frame(maxWidth: .infinity).padding(.vertical, 7)
                    }.buttonStyle(.borderedProminent).controlSize(.large).accessibilityIdentifier("importDocument")
                    if let storeError = store.error {
                        Label(storeError, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                        Button("Retry loading configuration") { store.reload() }
                    }
                    HStack {
                        Text("Your pipelines").font(.title2.bold())
                        Spacer()
                        Button { editing = Pipeline() } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                            .accessibilityLabel("New pipeline").accessibilityIdentifier("newPipeline")
                            .disabled(store.error != nil)
                    }
                    if store.configuration.pipelines.isEmpty {
                        VStack(alignment: .leading, spacing: 12) {
                            Image(systemName: "arrow.trianglehead.branch").font(.largeTitle).foregroundStyle(.teal)
                            Text("Create your first pipeline").font(.headline)
                            Text("Combine OCR and filename templates. Add a destination folder to save automatically.")
                                .foregroundStyle(.secondary)
                            Button("Create pipeline") { editing = Pipeline() }.buttonStyle(.bordered).disabled(store.error != nil)
                        }.padding(20).frame(maxWidth: .infinity, alignment: .leading)
                            .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 22))
                    } else {
                        ForEach(store.configuration.pipelines) { pipeline in
                            Button { editing = pipeline } label: {
                                VStack(alignment: .leading, spacing: 10) {
                                    HStack {
                                        Image(systemName: pipeline.unattended ? "bolt.fill" : "arrow.trianglehead.branch").foregroundStyle(.teal)
                                        Text(pipeline.name).font(.headline).foregroundStyle(.primary)
                                        Spacer()
                                        if store.configuration.defaultID == pipeline.id {
                                            Text("DEFAULT").font(.caption2.bold()).padding(.horizontal, 8).padding(.vertical, 5)
                                                .background(.teal.opacity(0.12), in: Capsule()).foregroundStyle(.teal)
                                        }
                                        Image(systemName: "chevron.right").font(.caption).foregroundStyle(.secondary)
                                    }
                                    Text(pipeline.summary.isEmpty ? "Keep PDF unchanged" : pipeline.summary)
                                        .font(.subheadline).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                                    Text(pipeline.unattended ? "Runs unattended" : "Review before export")
                                        .font(.caption).foregroundStyle(.secondary)
                                }.padding(18).background(.thinMaterial, in: RoundedRectangle(cornerRadius: 20))
                            }.buttonStyle(.plain)
                             .contextMenu {
                                 Button("Duplicate", systemImage: "plus.square.on.square") { perform { try store.duplicate(pipeline) } }
                                 Button("Delete", systemImage: "trash", role: .destructive) { perform { try store.delete(pipeline) } }
                             }
                        }
                    }
                    VStack(alignment: .leading, spacing: 8) {
                        Label("No document library", systemImage: "lock.shield")
                        Text("Share a PDF, JPEG, or PNG to PdfPipe from another app. Working copies are temporary; your pipelines stay.")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    #if DEBUG
                    if ProcessInfo.processInfo.arguments.contains("--ui-testing") {
                        Button("Open test document") { openFixture() }.accessibilityIdentifier("openFixture")
                    }
                    #endif
                }.padding(22)
            }
            .navigationTitle("PdfPipe")
            .sheet(item: $editing) { pipeline in
                PipelineEditor(store: store, pipeline: pipeline, isDefault: store.configuration.defaultID == pipeline.id)
            }
            .sheet(isPresented: Binding(get: { session != nil }, set: { _ in })) {
                if let session { WorkbenchView(model: session, store: store) }
            }
            .fileImporter(isPresented: $importing, allowedContentTypes: [.pdf, .jpeg, .png]) { result in
                switch result {
                case .success(let url): open(url, autoRun: false)
                case .failure(let error): self.error = error.localizedDescription
                }
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
            .alert("PdfPipe", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
                Button("OK") { error = nil }
            } message: { Text(error ?? "") }
        }.tint(.teal)
    }

    private func perform(_ action: () throws -> Void) { do { try action() } catch { self.error = error.localizedDescription } }

    private func open(_ url: URL, autoRun: Bool) {
        let model = DocumentSessionModel()
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
