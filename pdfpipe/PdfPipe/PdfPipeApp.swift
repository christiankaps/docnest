import SwiftUI

@main
struct PdfPipeApp: App {
    @StateObject private var store = PipelineStore()
    var body: some Scene { WindowGroup { HomeView(store: store) } }
}
