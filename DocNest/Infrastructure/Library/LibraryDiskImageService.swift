import AppKit
import Foundation
import LocalAuthentication
import Security

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

    enum Error: LocalizedError {
        case commandFailed(String)
        case invalidAttachResponse
        case missingMountPoint
        case invalidPassword
        case passwordMismatch
        case cancelled

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
            }
        }
    }

    private static let defaultMaximumImageSize = "256g"
    private static let keychainService = "com.kaps.docnest.library"

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

        let alert = NSAlert()
        alert.messageText = "Create Encrypted Library"
        alert.informativeText = "The library will use a macOS-encrypted sparsebundle."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = accessoryContainer(for: stack)

        guard alert.runModal() == .alertFirstButtonReturn else {
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

        let alert = NSAlert()
        alert.messageText = "Unlock Encrypted Library"
        alert.informativeText = "DocNest needs the library password to mount the encrypted sparsebundle."
        alert.addButton(withTitle: "Unlock")
        alert.addButton(withTitle: "Cancel")
        alert.accessoryView = accessoryContainer(for: stack)

        guard alert.runModal() == .alertFirstButtonReturn else {
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

    static func detach(_ mountedVolume: MountedVolume) throws {
        _ = try runHdiutil(arguments: ["detach", mountedVolume.deviceEntry, "-force"])
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

        let container = NSView(frame: NSRect(x: 0, y: 0, width: 380, height: 1))
        container.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(content)

        NSLayoutConstraint.activate([
            container.widthAnchor.constraint(equalToConstant: 380),
            content.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            content.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            content.topAnchor.constraint(equalTo: container.topAnchor),
            content.bottomAnchor.constraint(equalTo: container.bottomAnchor)
        ])

        return container
    }
}
