import AppKit
import Foundation
import LocalAuthentication
import ObjectiveC
import Security

private final class ModalActionTarget: NSObject {
    let handler: () -> Void

    init(handler: @escaping () -> Void) {
        self.handler = handler
    }

    @objc func performAction(_ sender: Any?) {
        handler()
    }
}

enum LibraryDiskImageService {
    struct MountedVolume: Equatable {
        let imageURL: URL
        let mountPointURL: URL
        let deviceEntry: String
    }

    struct EncryptionConfiguration {
        let password: String
        let savePasswordInKeychain: Bool
    }

    struct PasswordChangeConfiguration {
        let currentPassword: String
        let newPassword: String
        let savePasswordInKeychain: Bool
    }

    enum Error: LocalizedError {
        case commandFailed(String)
        case invalidAttachResponse
        case missingMountPoint
        case invalidPassword
        case passwordMismatch
        case cancelled
        case newPasswordMatchesCurrent
        case mountedElsewhere

        var errorDescription: String? {
            switch self {
            case .commandFailed(let message):
                return message
            case .invalidAttachResponse:
                return "DocNest could not determine the mounted sparsebundle volume."
            case .missingMountPoint:
                return "The encrypted library image mounted without a usable volume path."
            case .invalidPassword:
                return "The password for the encrypted library was invalid."
            case .passwordMismatch:
                return "The two passwords did not match."
            case .cancelled:
                return "The encrypted library action was cancelled."
            case .newPasswordMatchesCurrent:
                return "Choose a new password that is different from the current password."
            case .mountedElsewhere:
                return "The encrypted library is still mounted elsewhere. Eject it and try again."
            }
        }
    }

    private static let defaultMaximumImageSize = "256g"
    private static let keychainService = "com.kaps.docnest.library"

    @MainActor
    static func promptForEncryptionConfiguration(libraryName: String) -> EncryptionConfiguration? {
        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let confirmField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let saveCheckbox = NSButton(checkboxWithTitle: "Save password in Keychain for Touch ID unlock on this Mac", target: nil, action: nil)
        saveCheckbox.state = .on

        let stack = NSStackView(views: [
            labelField("Create an encrypted library for \(libraryName)."),
            fieldRow(label: "Password", field: passwordField),
            fieldRow(label: "Confirm", field: confirmField),
            saveCheckbox
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading

        guard runFormPanel(
            title: "Create Encrypted Library",
            message: "The library will use a macOS-encrypted sparsebundle.",
            confirmTitle: "Create",
            content: stack,
            initialFirstResponder: passwordField
        ) else {
            return nil
        }

        let password = passwordField.stringValue
        let confirmation = confirmField.stringValue

        guard !password.isEmpty else {
            NSAlert(error: Error.invalidPassword).runModal()
            return promptForEncryptionConfiguration(libraryName: libraryName)
        }

        guard password == confirmation else {
            NSAlert(error: Error.passwordMismatch).runModal()
            return promptForEncryptionConfiguration(libraryName: libraryName)
        }

        return EncryptionConfiguration(
            password: password,
            savePasswordInKeychain: saveCheckbox.state == .on
        )
    }

    @MainActor
    static func promptForUnlockPassword(libraryName: String) -> EncryptionConfiguration? {
        let passwordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let saveCheckbox = NSButton(checkboxWithTitle: "Save password in Keychain for Touch ID unlock on this Mac", target: nil, action: nil)
        saveCheckbox.state = .off

        let stack = NSStackView(views: [
            labelField("Enter the password for \(libraryName)."),
            fieldRow(label: "Password", field: passwordField),
            saveCheckbox
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading

        guard runFormPanel(
            title: "Unlock Encrypted Library",
            message: "DocNest needs the library password to mount the encrypted sparsebundle.",
            confirmTitle: "Unlock",
            content: stack,
            initialFirstResponder: passwordField
        ) else {
            return nil
        }

        let password = passwordField.stringValue
        guard !password.isEmpty else {
            NSAlert(error: Error.invalidPassword).runModal()
            return promptForUnlockPassword(libraryName: libraryName)
        }

        return EncryptionConfiguration(
            password: password,
            savePasswordInKeychain: saveCheckbox.state == .on
        )
    }

    @MainActor
    static func promptForPasswordChange(
        libraryName: String,
        savePasswordInitially: Bool = true
    ) -> PasswordChangeConfiguration? {
        let currentPasswordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let newPasswordField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let confirmField = NSSecureTextField(frame: NSRect(x: 0, y: 0, width: 280, height: 24))
        let saveCheckbox = NSButton(checkboxWithTitle: "Save new password in Keychain for Touch ID unlock on this Mac", target: nil, action: nil)
        saveCheckbox.state = savePasswordInitially ? .on : .off

        let stack = NSStackView(views: [
            labelField("Change the password for \(libraryName)."),
            fieldRow(label: "Current", field: currentPasswordField),
            fieldRow(label: "New", field: newPasswordField),
            fieldRow(label: "Confirm", field: confirmField),
            saveCheckbox
        ])
        stack.orientation = .vertical
        stack.spacing = 10
        stack.alignment = .leading

        guard runFormPanel(
            title: "Change Library Password",
            message: "DocNest will update the encrypted sparsebundle password for this library.",
            confirmTitle: "Change Password",
            content: stack,
            initialFirstResponder: currentPasswordField
        ) else {
            return nil
        }

        let currentPassword = currentPasswordField.stringValue
        let newPassword = newPasswordField.stringValue
        let confirmation = confirmField.stringValue

        guard !currentPassword.isEmpty, !newPassword.isEmpty else {
            NSAlert(error: Error.invalidPassword).runModal()
            return promptForPasswordChange(
                libraryName: libraryName,
                savePasswordInitially: saveCheckbox.state == .on
            )
        }

        guard newPassword == confirmation else {
            NSAlert(error: Error.passwordMismatch).runModal()
            return promptForPasswordChange(
                libraryName: libraryName,
                savePasswordInitially: saveCheckbox.state == .on
            )
        }

        guard currentPassword != newPassword else {
            NSAlert(error: Error.newPasswordMatchesCurrent).runModal()
            return promptForPasswordChange(
                libraryName: libraryName,
                savePasswordInitially: saveCheckbox.state == .on
            )
        }

        return PasswordChangeConfiguration(
            currentPassword: currentPassword,
            newPassword: newPassword,
            savePasswordInKeychain: saveCheckbox.state == .on
        )
    }

    static func createEncryptedSparsebundle(
        at imageURL: URL,
        volumeName: String,
        password: String,
        maximumSize: String = defaultMaximumImageSize
    ) throws {
        try FileManager.default.createDirectory(
            at: imageURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        _ = try runHdiutil(
            arguments: [
                "create",
                imageURL.path,
                "-type", "SPARSEBUNDLE",
                "-fs", "APFS",
                "-volname", volumeName,
                "-size", maximumSize,
                "-stdinpass",
                "-encryption", "AES-256",
                "-plist"
            ],
            stdin: password + "\n"
        )
    }

    static func attachSparsebundle(at imageURL: URL, password: String) throws -> MountedVolume {
        if let existing = try findMountedVolume(for: imageURL) {
            return existing
        }

        let data = try runHdiutil(
            arguments: [
                "attach",
                imageURL.path,
                "-stdinpass",
                "-plist",
                "-nobrowse",
                "-mountRandom", "/private/tmp"
            ],
            stdin: password + "\n"
        )

        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let entities = plist["system-entities"] as? [[String: Any]] else {
            throw Error.invalidAttachResponse
        }

        for entity in entities {
            if let mountPath = entity["mount-point"] as? String,
               let deviceEntry = entity["dev-entry"] as? String {
                return MountedVolume(
                    imageURL: imageURL.standardizedFileURL,
                    mountPointURL: URL(fileURLWithPath: mountPath, isDirectory: true).standardizedFileURL,
                    deviceEntry: deviceEntry
                )
            }
        }

        throw Error.missingMountPoint
    }

    static func detach(_ mountedVolume: MountedVolume, force: Bool = false) throws {
        var arguments = ["detach", mountedVolume.deviceEntry]
        if force {
            arguments.append("-force")
        }
        _ = try runHdiutil(arguments: arguments)
    }

    static func changePassword(
        forSparsebundle imageURL: URL,
        currentPassword: String,
        newPassword: String
    ) throws {
        _ = try runHdiutil(
            arguments: [
                "chpass",
                imageURL.path,
                "-oldstdinpass",
                "-newstdinpass"
            ],
            stdin: currentPassword + "\n" + newPassword + "\n"
        )
    }

    static func validatePasswordChange(
        forSparsebundle imageURL: URL,
        currentPassword: String,
        newPassword: String
    ) throws {
        let clonedImageURL = imageURL.deletingLastPathComponent()
            .appendingPathComponent(".PasswordValidation-\(UUID().uuidString).sparsebundle", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: clonedImageURL)
        }

        try FileManager.default.copyItem(at: imageURL, to: clonedImageURL)
        try changePassword(
            forSparsebundle: clonedImageURL,
            currentPassword: currentPassword,
            newPassword: newPassword
        )
    }

    static func findMountedVolume(for imageURL: URL) throws -> MountedVolume? {
        let data = try runHdiutil(arguments: ["info", "-plist"])
        guard let plist = try PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let images = plist["images"] as? [[String: Any]] else {
            return nil
        }

        let standardizedPath = imageURL.standardizedFileURL.path
        for image in images {
            guard let imagePath = image["image-path"] as? String,
                  URL(fileURLWithPath: imagePath).standardizedFileURL.path == standardizedPath,
                  let entities = image["system-entities"] as? [[String: Any]] else {
                continue
            }

            for entity in entities {
                if let mountPath = entity["mount-point"] as? String,
                   let deviceEntry = entity["dev-entry"] as? String {
                    return MountedVolume(
                        imageURL: imageURL.standardizedFileURL,
                        mountPointURL: URL(fileURLWithPath: mountPath, isDirectory: true).standardizedFileURL,
                        deviceEntry: deviceEntry
                    )
                }
            }
        }

        return nil
    }

    static func savePasswordInKeychain(_ password: String, libraryID: UUID) throws {
        try deletePasswordFromKeychain(libraryID: libraryID)

        let access = SecAccessControlCreateWithFlags(
            nil,
            kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            .userPresence,
            nil
        )

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: libraryID.uuidString,
            kSecUseDataProtectionKeychain as String: true,
            kSecValueData as String: Data(password.utf8),
            kSecAttrAccessControl as String: access as Any
        ]

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func passwordFromKeychain(libraryID: UUID, prompt: String) throws -> String? {
        let context = LAContext()
        context.localizedReason = prompt

        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: libraryID.uuidString,
            kSecUseDataProtectionKeychain as String: true,
            kSecReturnData as String: true,
            kSecUseAuthenticationContext as String: context
        ]

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)
        switch status {
        case errSecSuccess:
            guard let data = item as? Data,
                  let password = String(data: data, encoding: .utf8) else {
                return nil
            }
            return password
        case errSecItemNotFound, errSecUserCanceled, errSecAuthFailed:
            return nil
        default:
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    static func deletePasswordFromKeychain(libraryID: UUID) throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: libraryID.uuidString,
            kSecUseDataProtectionKeychain as String: true
        ]

        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw NSError(domain: NSOSStatusErrorDomain, code: Int(status))
        }
    }

    private static func runHdiutil(arguments: [String], stdin: String? = nil) throws -> Data {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/hdiutil")
        process.arguments = arguments

        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe

        if let stdin {
            let inputPipe = Pipe()
            process.standardInput = inputPipe
            try process.run()
            if let data = stdin.data(using: .utf8) {
                inputPipe.fileHandleForWriting.write(data)
            }
            try? inputPipe.fileHandleForWriting.close()
        } else {
            try process.run()
        }

        process.waitUntilExit()

        let outputData = outputPipe.fileHandleForReading.readDataToEndOfFile()
        let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()

        guard process.terminationStatus == 0 else {
            let errorMessage = String(data: errorData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            throw Error.commandFailed(errorMessage?.isEmpty == false ? errorMessage! : "hdiutil failed with exit code \(process.terminationStatus).")
        }

        return outputData
    }

    private static func labelField(_ string: String) -> NSTextField {
        let label = NSTextField(labelWithString: string)
        label.lineBreakMode = .byWordWrapping
        label.maximumNumberOfLines = 0
        label.preferredMaxLayoutWidth = 360
        return label
    }

    private static func fieldRow(label: String, field: NSTextField) -> NSView {
        let title = NSTextField(labelWithString: label)
        title.alignment = .right
        title.font = .systemFont(ofSize: NSFont.systemFontSize)
        title.setContentHuggingPriority(.required, for: .horizontal)
        title.setContentCompressionResistancePriority(.required, for: .horizontal)
        title.widthAnchor.constraint(equalToConstant: 72).isActive = true

        field.translatesAutoresizingMaskIntoConstraints = false
        field.widthAnchor.constraint(equalToConstant: 250).isActive = true

        let stack = NSStackView(views: [title, field])
        stack.orientation = .horizontal
        stack.spacing = 8
        stack.alignment = .firstBaseline
        stack.translatesAutoresizingMaskIntoConstraints = false
        return stack
    }

    private static func accessoryContainer(for content: NSStackView) -> NSView {
        content.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 160))
        container.addSubview(content)

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        container.layoutSubtreeIfNeeded()
        let fittingSize = container.fittingSize
        container.frame = NSRect(origin: .zero, size: fittingSize)

        return container
    }

    @MainActor
    private static func runFormPanel(
        title: String,
        message: String,
        confirmTitle: String,
        content: NSStackView,
        initialFirstResponder: NSView?
    ) -> Bool {
        let titleLabel = NSTextField(labelWithString: title)
        titleLabel.font = .systemFont(ofSize: 20, weight: .semibold)

        let messageLabel = NSTextField(labelWithString: message)
        messageLabel.lineBreakMode = .byWordWrapping
        messageLabel.maximumNumberOfLines = 0
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.preferredMaxLayoutWidth = 420

        let cancelButton = NSButton(title: "Cancel", target: nil, action: nil)
        cancelButton.keyEquivalent = "\u{1b}"
        cancelButton.bezelStyle = .rounded

        let confirmButton = NSButton(title: confirmTitle, target: nil, action: nil)
        confirmButton.keyEquivalent = "\r"
        confirmButton.bezelStyle = .rounded

        let buttonRow = NSStackView(views: [cancelButton, confirmButton])
        buttonRow.orientation = .horizontal
        buttonRow.spacing = 8
        buttonRow.alignment = .centerY
        buttonRow.distribution = .gravityAreas
        buttonRow.setHuggingPriority(.required, for: .vertical)

        let rootStack = NSStackView(views: [titleLabel, messageLabel, content, buttonRow])
        rootStack.orientation = .vertical
        rootStack.spacing = 14
        rootStack.alignment = .leading
        rootStack.translatesAutoresizingMaskIntoConstraints = false

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 460, height: 220))
        container.addSubview(rootStack)

        NSLayoutConstraint.activate([
            rootStack.leadingAnchor.constraint(equalTo: container.leadingAnchor, constant: 24),
            rootStack.trailingAnchor.constraint(equalTo: container.trailingAnchor, constant: -24),
            rootStack.topAnchor.constraint(equalTo: container.topAnchor, constant: 24),
            rootStack.bottomAnchor.constraint(equalTo: container.bottomAnchor, constant: -20),
            content.widthAnchor.constraint(equalToConstant: 412)
        ])

        container.layoutSubtreeIfNeeded()
        let fittingSize = container.fittingSize
        container.frame = NSRect(origin: .zero, size: fittingSize)

        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: fittingSize),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        panel.title = title
        panel.isReleasedWhenClosed = false
        panel.contentView = container
        panel.standardWindowButton(.zoomButton)?.isHidden = true
        panel.standardWindowButton(.miniaturizeButton)?.isHidden = true
        panel.center()

        var result = false
        let confirmTarget = ModalActionTarget {
            result = true
            NSApp.stopModal(withCode: .OK)
            panel.orderOut(nil)
        }
        let cancelTarget = ModalActionTarget {
            result = false
            NSApp.stopModal(withCode: .cancel)
            panel.orderOut(nil)
        }

        confirmButton.target = confirmTarget
        confirmButton.action = #selector(ModalActionTarget.performAction(_:))
        cancelButton.target = cancelTarget
        cancelButton.action = #selector(ModalActionTarget.performAction(_:))

        objc_setAssociatedObject(panel, "confirmTarget", confirmTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        objc_setAssociatedObject(panel, "cancelTarget", cancelTarget, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        if let initialFirstResponder {
            panel.makeFirstResponder(initialFirstResponder)
        }
        _ = NSApp.runModal(for: panel)
        return result
    }
}
