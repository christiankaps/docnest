import SwiftUI

@main
struct PdfPipeApp: App {
    @StateObject private var store = PipelineStore()

    init() {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing"),
           let suite = process.environment["PDFPIPE_UI_TEST_CONFIGURATION_SUITE"],
           let defaults = UserDefaults(suiteName: suite) {
            _store = StateObject(wrappedValue: PipelineStore(defaults: defaults))
        }
        #endif
    }

    var body: some Scene { WindowGroup { HomeView(store: store) } }
}
