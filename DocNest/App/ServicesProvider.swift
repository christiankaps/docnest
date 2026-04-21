import AppKit

/// Handles macOS Services requests for importing supported files into DocNest.
@MainActor
final class ServicesProvider: NSObject {
    /// Posted when files are received via the Services menu.
    /// The notification's `object` is an array of `URL`.
    static let didReceiveFilesNotification = Notification.Name("DocNestServicesDidReceiveFiles")

    /// Called by the system when the user selects "Import into DocNest" from a Services-integrated menu.
    /// The selector name must match the NSMessage value in Info.plist.
    @objc func importFiles(
        _ pboard: NSPasteboard,
        userData: String,
        error errorPointer: AutoreleasingUnsafeMutablePointer<NSString?>
    ) {
        guard let urls = pboard.readObjects(forClasses: [NSURL.self]) as? [URL], !urls.isEmpty else {
            errorPointer.pointee = "No files found on the pasteboard." as NSString
            return
        }

        let supportedURLs = urls.filter { url in
            ImportPDFDocumentsUseCase.containsImportableDocuments(in: [url])
        }

        guard !supportedURLs.isEmpty else {
            errorPointer.pointee = "No supported files were found. DocNest supports PDFs, ZIP archives, and folders containing PDFs." as NSString
            return
        }

        NSApplication.shared.activate(ignoringOtherApps: true)

        NotificationCenter.default.post(
            name: Self.didReceiveFilesNotification,
            object: supportedURLs
        )
    }
}
