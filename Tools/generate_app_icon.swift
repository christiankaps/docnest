import AppKit
import Foundation
import ImageIO

struct IconSpec {
    let size: String
    let scale: String
    let filenameSuffix: String
    let pixels: Int
}

struct IconSourceCrop {
    let rect: CGRect
    let mask: IconMask
}

enum IconMask {
    case app
    case libraryPackage
}

enum IconPreviewVariant: String, CaseIterable {
    case light = "AppIconLight.png"
    case dark = "AppIconDark.png"
    case tinted = "AppIconTinted.png"
}

let repositoryRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
let appIconDirectory = repositoryRoot
    .appendingPathComponent("DocNest/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let iconVariantDirectory = repositoryRoot
    .appendingPathComponent("design/icons", isDirectory: true)
let iconFamilySourceURL = iconVariantDirectory
    .appendingPathComponent("DocNestIconFamilySource.png")
let libraryIconURL = repositoryRoot
    .appendingPathComponent("DocNest/Resources/DocNestLibrary.icns")

let iconSpecs = [
    IconSpec(size: "16x16", scale: "1x", filenameSuffix: "16x16", pixels: 16),
    IconSpec(size: "16x16", scale: "2x", filenameSuffix: "16x16@2x", pixels: 32),
    IconSpec(size: "32x32", scale: "1x", filenameSuffix: "32x32", pixels: 32),
    IconSpec(size: "32x32", scale: "2x", filenameSuffix: "32x32@2x", pixels: 64),
    IconSpec(size: "128x128", scale: "1x", filenameSuffix: "128x128", pixels: 128),
    IconSpec(size: "128x128", scale: "2x", filenameSuffix: "128x128@2x", pixels: 256),
    IconSpec(size: "256x256", scale: "1x", filenameSuffix: "256x256", pixels: 256),
    IconSpec(size: "256x256", scale: "2x", filenameSuffix: "256x256@2x", pixels: 512),
    IconSpec(size: "512x512", scale: "1x", filenameSuffix: "512x512", pixels: 512),
    IconSpec(size: "512x512", scale: "2x", filenameSuffix: "512x512@2x", pixels: 1024)
]

let appIconCrop = IconSourceCrop(
    rect: CGRect(x: 192, y: 118, width: 646, height: 646),
    mask: .app
)
let libraryPackageCrop = IconSourceCrop(
    rect: CGRect(x: 1003, y: 101, width: 653, height: 653),
    mask: .libraryPackage
)

try FileManager.default.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconVariantDirectory, withIntermediateDirectories: true)

let sourceImage = try loadSourceImage()
try generateAppIconSet(from: sourceImage)
try generateAppIconVariantPreviews(from: sourceImage)
try generateLibraryPackageIcon(from: sourceImage)

func loadSourceImage() throws -> CGImage {
    guard
        let imageSource = CGImageSourceCreateWithURL(iconFamilySourceURL as CFURL, nil),
        let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil)
    else {
        throw NSError(domain: "DocNestIconGenerator", code: 1, userInfo: [
            NSLocalizedDescriptionKey: "Unable to load icon source at \(iconFamilySourceURL.path)"
        ])
    }

    return image
}

func removeExistingPNGs(in directory: URL) throws {
    let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    for fileURL in contents where fileURL.pathExtension == "png" {
        try FileManager.default.removeItem(at: fileURL)
    }
}

func generateAppIconSet(from sourceImage: CGImage) throws {
    try removeExistingPNGs(in: appIconDirectory)

    var imagesJSON: [String] = []

    for spec in iconSpecs {
        let filename = "icon_\(spec.filenameSuffix).png"
        let image = try renderIcon(from: sourceImage, crop: appIconCrop, pixels: spec.pixels)

        try writePNG(image, to: appIconDirectory.appendingPathComponent(filename))
        imagesJSON.append(contentsJSONEntry(filename: filename, spec: spec))
    }

    let contents = """
    {
      "images" : [
    \(imagesJSON.joined(separator: ",\n"))
      ],
      "info" : {
        "author" : "xcode",
        "version" : 1
      }
    }
    """

    try contents.write(to: appIconDirectory.appendingPathComponent("Contents.json"), atomically: true, encoding: .utf8)
}

func generateAppIconVariantPreviews(from sourceImage: CGImage) throws {
    for variant in IconPreviewVariant.allCases {
        let image = try renderIcon(from: sourceImage, crop: appIconCrop, pixels: 1024, previewVariant: variant)
        try writePNG(image, to: iconVariantDirectory.appendingPathComponent(variant.rawValue))
    }

    let libraryPreview = try renderIcon(from: sourceImage, crop: libraryPackageCrop, pixels: 1024)
    try writePNG(libraryPreview, to: iconVariantDirectory.appendingPathComponent("DocNestLibraryPackage.png"))
}

func contentsJSONEntry(filename: String, spec: IconSpec) -> String {
    return """
        {
          "filename" : "\(filename)",
          "idiom" : "mac",
          "scale" : "\(spec.scale)",
          "size" : "\(spec.size)"
        }
    """
}

func generateLibraryPackageIcon(from sourceImage: CGImage) throws {
    let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("docnest-library.iconset", isDirectory: true)
    try? FileManager.default.removeItem(at: iconsetURL)
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    for spec in iconSpecs {
        let filename = "icon_\(spec.filenameSuffix).png"
        let image = try renderIcon(from: sourceImage, crop: libraryPackageCrop, pixels: spec.pixels)
        try writePNG(image, to: iconsetURL.appendingPathComponent(filename))
    }

    try? FileManager.default.removeItem(at: libraryIconURL)

    let process = Process()
    process.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
    process.arguments = ["-c", "icns", iconsetURL.path, "-o", libraryIconURL.path]
    try process.run()
    process.waitUntilExit()

    guard process.terminationStatus == 0 else {
        throw NSError(domain: "DocNestIconGenerator", code: Int(process.terminationStatus))
    }

    try? FileManager.default.removeItem(at: iconsetURL)
}

func renderIcon(
    from sourceImage: CGImage,
    crop: IconSourceCrop,
    pixels: Int,
    previewVariant: IconPreviewVariant? = nil
) throws -> NSImage {
    guard let croppedImage = sourceImage.cropping(to: crop.rect) else {
        throw NSError(domain: "DocNestIconGenerator", code: 2, userInfo: [
            NSLocalizedDescriptionKey: "Unable to crop source image with rect \(crop.rect)"
        ])
    }

    let outputSize = NSSize(width: pixels, height: pixels)
    return NSImage(size: outputSize, flipped: false) { rect in
        NSGraphicsContext.current?.imageInterpolation = .high

        NSGraphicsContext.saveGraphicsState()
        maskPath(for: crop.mask, in: rect).addClip()

        let image = NSImage(cgImage: croppedImage, size: outputSize)
        image.draw(in: rect, from: NSRect(origin: .zero, size: outputSize), operation: .sourceOver, fraction: 1)
        if let previewVariant {
            applyPreviewAdjustment(previewVariant, in: rect)
        }

        NSGraphicsContext.restoreGraphicsState()
        return true
    }
}

func applyPreviewAdjustment(_ variant: IconPreviewVariant, in rect: CGRect) {
    let overlayPath = NSBezierPath(rect: rect)

    switch variant {
    case .light:
        break
    case .dark:
        NSColor.black.withAlphaComponent(0.24).setFill()
        overlayPath.fill()
        NSColor(srgbRed: 0.03, green: 0.11, blue: 0.14, alpha: 0.18).setFill()
        overlayPath.fill()
    case .tinted:
        NSColor(srgbRed: 0.78, green: 0.83, blue: 0.88, alpha: 0.28).setFill()
        overlayPath.fill()
        NSColor.white.withAlphaComponent(0.10).setFill()
        overlayPath.fill()
    }
}

func maskPath(for mask: IconMask, in rect: CGRect) -> NSBezierPath {
    switch mask {
    case .app:
        return NSBezierPath(
            roundedRect: rect.insetBy(dx: rect.width * 0.012, dy: rect.height * 0.012),
            xRadius: rect.width * 0.205,
            yRadius: rect.height * 0.205
        )
    case .libraryPackage:
        let path = NSBezierPath()
        let stackRect = CGRect(
            x: rect.minX + rect.width * 0.075,
            y: rect.minY + rect.height * 0.035,
            width: rect.width * 0.835,
            height: rect.height * 0.245
        )
        let documentRect = CGRect(
            x: rect.minX + rect.width * 0.075,
            y: rect.minY + rect.height * 0.125,
            width: rect.width * 0.835,
            height: rect.height * 0.825
        )

        path.append(NSBezierPath(
            roundedRect: stackRect,
            xRadius: rect.width * 0.055,
            yRadius: rect.width * 0.055
        ))
        path.append(NSBezierPath(
            roundedRect: documentRect,
            xRadius: rect.width * 0.075,
            yRadius: rect.width * 0.075
        ))
        return path
    }
}

func writePNG(_ image: NSImage, to fileURL: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "DocNestIconGenerator", code: 3)
    }

    try pngData.write(to: fileURL)
}
