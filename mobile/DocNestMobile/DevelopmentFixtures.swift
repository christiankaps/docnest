#if DEBUG
import PDFKit
import UIKit
import LocalAuthentication

/// Synthetic data only. Release builds contain neither fixture generation nor test launch routing.
@MainActor
enum DevelopmentFixtures {
    static var testRoot: URL? {
        guard let token = ProcessInfo.processInfo.environment["DOCNEST_UI_TEST_SESSION"], UUID(uuidString: token) != nil else { return nil }
        return URL.applicationSupportDirectory.appending(path: "UITests/\(token)")
    }

    static var testDefaults: UserDefaults? {
        guard testRoot != nil, let token = ProcessInfo.processInfo.environment["DOCNEST_UI_TEST_SESSION"] else { return nil }
        let defaults = UserDefaults(suiteName: "DocNestMobile.UITests.\(token)")
        if ProcessInfo.processInfo.environment["DOCNEST_UI_TEST_LOCK_ENABLED"] == "1" { defaults?.set(true, forKey: "libraryLockEnabled") }
        return defaults
    }

    static var testAuthenticator: (any LibraryAuthenticating)? {
        guard testRoot != nil, let outcome = ProcessInfo.processInfo.environment["DOCNEST_UI_TEST_AUTH"],
              ["success", "failure"].contains(outcome) else { return nil }
        return FixtureAuthenticator(succeeds: outcome == "success")
    }

    static func seed(_ store: LibraryStore) async throws {
        guard ProcessInfo.processInfo.environment["DOCNEST_UI_TEST_SEED"] == "1" else { return }
        guard try await store.load().isEmpty else { return }
        let folder = URL.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: folder) }
        let source = folder.appending(path: "Invoice.pdf")
        // Keep year-filter UI checks reproducible independently of the simulator clock.
        let importedAt = Calendar(identifier: .gregorian).date(from: DateComponents(year: 2026, month: 10, day: 10, hour: 12))!
        try pdf(text: "Synthetic invoice ALPHA-123", pages: 2).write(to: source)
        _ = try await store.importPDF(from: source, importedAt: importedAt)
        try pdf(text: "Synthetic receipt BETA-456", pages: 1).write(to: source)
        _ = try await store.importPDF(from: source, importedAt: importedAt)
    }

    static func pdf(text: String, pages: Int, image: UIImage? = nil) -> Data {
        UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 595, height: 842)).pdfData { context in
            for page in 0..<pages {
                context.beginPage()
                image?.draw(in: CGRect(x: 25, y: 80, width: 545, height: 700))
                let line = "\(text) — Page \(page + 1)"
                (line as NSString).draw(at: CGPoint(x: 30, y: 30), withAttributes: [.font: UIFont.systemFont(ofSize: 18)])
            }
        }
    }
}
@MainActor
private final class FixtureAuthenticator: LibraryAuthenticating {
    let succeeds: Bool
    init(succeeds: Bool) { self.succeeds = succeeds }
    func authenticate(reason: String) async throws { if !succeeds { throw LAError(.authenticationFailed) } }
    func cancel() {}
}
#endif
