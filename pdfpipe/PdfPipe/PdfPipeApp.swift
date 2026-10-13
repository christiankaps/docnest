import SwiftUI

@main
struct PdfPipeApp: App {
    @StateObject private var settings = OneFlowSettingsStore()

    init() {
        #if DEBUG
        let process = ProcessInfo.processInfo
        if process.arguments.contains("--ui-testing"),
           let suite = process.environment["PDFPIPE_UI_TEST_CONFIGURATION_SUITE"],
           let defaults = UserDefaults(suiteName: suite) {
            _settings = StateObject(wrappedValue: OneFlowSettingsStore(defaults: defaults))
        }
        #endif
    }

    var body: some Scene { WindowGroup { OneFlowHomeView(settings: settings) } }
}
