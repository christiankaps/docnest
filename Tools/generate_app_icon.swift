import AppKit
import Foundation

struct IconSpec {
    let size: String
    let scale: String
    let filenameSuffix: String
    let pixels: Int
}

enum AppIconAppearance: String, CaseIterable {
    case light
    case dark
    case tinted
}

let appIconDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("DocNest/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)
let iconVariantDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("design/icons", isDirectory: true)
let libraryIconURL = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
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

try FileManager.default.createDirectory(at: appIconDirectory, withIntermediateDirectories: true)
try FileManager.default.createDirectory(at: iconVariantDirectory, withIntermediateDirectories: true)
try generateAppIcons()
try generateLibraryPackageIcon()

func removeExistingPNGs(in directory: URL) throws {
    let contents = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
    for fileURL in contents where fileURL.pathExtension == "png" {
        try FileManager.default.removeItem(at: fileURL)
    }
}

func generateAppIcons() throws {
    try generateAppIconSet(for: .light)
    try generateAppIconVariantPreviews()
}

func generateAppIconSet(for appearance: AppIconAppearance) throws {
    try removeExistingPNGs(in: appIconDirectory)

    var imagesJSON: [String] = []

    for spec in iconSpecs {
        let filename = "icon_\(spec.filenameSuffix).png"
        let image = NSImage(size: NSSize(width: spec.pixels, height: spec.pixels), flipped: false) { rect in
            drawAppIcon(in: rect, appearance: appearance)
            return true
        }

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

func generateAppIconVariantPreviews() throws {
    let variants: [(AppIconAppearance, String)] = [
        (.light, "AppIconLight.png"),
        (.dark, "AppIconDark.png"),
        (.tinted, "AppIconTinted.png")
    ]

    for (appearance, filename) in variants {
        let image = NSImage(size: NSSize(width: 1024, height: 1024), flipped: false) { rect in
            drawAppIcon(in: rect, appearance: appearance)
            return true
        }
        try writePNG(image, to: iconVariantDirectory.appendingPathComponent(filename))
    }
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

func generateLibraryPackageIcon() throws {
    let iconsetURL = URL(fileURLWithPath: NSTemporaryDirectory())
        .appendingPathComponent("docnest-library.iconset", isDirectory: true)
    try? FileManager.default.removeItem(at: iconsetURL)
    try FileManager.default.createDirectory(at: iconsetURL, withIntermediateDirectories: true)

    for spec in iconSpecs {
        let filename = "icon_\(spec.filenameSuffix).png"
        let image = NSImage(size: NSSize(width: spec.pixels, height: spec.pixels), flipped: false) { rect in
            drawLibraryPackageIcon(in: rect)
            return true
        }
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

func writePNG(_ image: NSImage, to fileURL: URL) throws {
    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "DocNestIconGenerator", code: 1)
    }

    try pngData.write(to: fileURL)
}

func drawAppIcon(in rect: CGRect, appearance: AppIconAppearance) {
    NSGraphicsContext.current?.imageInterpolation = .high

    let insetRect = rect.insetBy(dx: rect.width * 0.055, dy: rect.height * 0.055)
    let cornerRadius = insetRect.width * 0.225
    let backgroundPath = NSBezierPath(roundedRect: insetRect, xRadius: cornerRadius, yRadius: cornerRadius)

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: appearance == .light ? 0.18 : 0.28)
    shadow.shadowBlurRadius = rect.width * 0.052
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.017)
    shadow.set()

    gradient(for: appearance).draw(in: backgroundPath, angle: -42)

    NSGraphicsContext.saveGraphicsState()
    backgroundPath.addClip()
    drawSoftHighlights(in: insetRect, appearance: appearance)
    drawDocumentStack(in: insetRect, appearance: appearance)
    drawValueTag(in: insetRect, appearance: appearance)
    NSGraphicsContext.restoreGraphicsState()

    stroke(for: appearance).setStroke()
    backgroundPath.lineWidth = max(1, rect.width * 0.01)
    backgroundPath.stroke()
}

func drawLibraryPackageIcon(in rect: CGRect) {
    NSGraphicsContext.current?.imageInterpolation = .high

    let inset = rect.width * 0.07
    let baseRect = rect.insetBy(dx: inset, dy: inset * 1.15)
    let folderBack = CGRect(x: baseRect.minX + baseRect.width * 0.05, y: baseRect.minY + baseRect.height * 0.15, width: baseRect.width * 0.86, height: baseRect.height * 0.68)
    let bodyRect = CGRect(x: folderBack.minX, y: folderBack.minY, width: folderBack.width, height: folderBack.height * 0.83)
    let tabRect = CGRect(
        x: folderBack.minX + folderBack.width * 0.06,
        y: bodyRect.maxY - folderBack.height * 0.08,
        width: folderBack.width * 0.34,
        height: folderBack.height * 0.23
    )

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.22)
    shadow.shadowBlurRadius = rect.width * 0.045
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.018)
    shadow.set()

    let tab = NSBezierPath(roundedRect: tabRect, xRadius: tabRect.height * 0.28, yRadius: tabRect.height * 0.28)
    NSGradient(colors: [
        NSColor(srgbRed: 0.30, green: 0.68, blue: 0.62, alpha: 1),
        NSColor(srgbRed: 0.18, green: 0.52, blue: 0.53, alpha: 1)
    ])?.draw(in: tab, angle: -12)

    let body = NSBezierPath(roundedRect: bodyRect, xRadius: bodyRect.width * 0.11, yRadius: bodyRect.width * 0.11)
    NSGradient(colors: [
        NSColor(srgbRed: 0.09, green: 0.37, blue: 0.42, alpha: 1),
        NSColor(srgbRed: 0.06, green: 0.24, blue: 0.32, alpha: 1)
    ])?.draw(in: body, angle: -38)

    NSGraphicsContext.saveGraphicsState()
    body.addClip()
    drawDocumentStack(in: bodyRect.insetBy(dx: -bodyRect.width * 0.03, dy: -bodyRect.height * 0.14), appearance: .dark)
    drawValueTag(in: bodyRect.insetBy(dx: -bodyRect.width * 0.04, dy: -bodyRect.height * 0.08), appearance: .dark)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.18).setStroke()
    body.lineWidth = max(1, rect.width * 0.008)
    body.stroke()
}

func gradient(for appearance: AppIconAppearance) -> NSGradient {
    switch appearance {
    case .light:
        NSGradient(colors: [
            NSColor(srgbRed: 0.92, green: 0.98, blue: 0.96, alpha: 1),
            NSColor(srgbRed: 0.36, green: 0.79, blue: 0.70, alpha: 1),
            NSColor(srgbRed: 0.96, green: 0.73, blue: 0.36, alpha: 1)
        ])!
    case .dark:
        NSGradient(colors: [
            NSColor(srgbRed: 0.02, green: 0.11, blue: 0.14, alpha: 1),
            NSColor(srgbRed: 0.04, green: 0.31, blue: 0.34, alpha: 1),
            NSColor(srgbRed: 0.54, green: 0.39, blue: 0.19, alpha: 1)
        ])!
    case .tinted:
        NSGradient(colors: [
            NSColor(srgbRed: 0.93, green: 0.95, blue: 0.98, alpha: 1),
            NSColor(srgbRed: 0.62, green: 0.66, blue: 0.73, alpha: 1),
            NSColor(srgbRed: 0.31, green: 0.36, blue: 0.45, alpha: 1)
        ])!
    }
}

func stroke(for appearance: AppIconAppearance) -> NSColor {
    switch appearance {
    case .light: NSColor.white.withAlphaComponent(0.68)
    case .dark: NSColor.white.withAlphaComponent(0.16)
    case .tinted: NSColor.white.withAlphaComponent(0.45)
    }
}

func drawSoftHighlights(in rect: CGRect, appearance: AppIconAppearance) {
    let topGlow = NSBezierPath(ovalIn: CGRect(x: rect.minX - rect.width * 0.2, y: rect.maxY - rect.height * 0.45, width: rect.width * 0.62, height: rect.height * 0.5))
    NSColor.white.withAlphaComponent(appearance == .dark ? 0.08 : 0.24).setFill()
    topGlow.fill()

    let lowerGlow = NSBezierPath(ovalIn: CGRect(x: rect.maxX - rect.width * 0.52, y: rect.minY + rect.height * 0.02, width: rect.width * 0.62, height: rect.height * 0.44))
    NSColor(srgbRed: 0.98, green: 0.82, blue: 0.52, alpha: appearance == .tinted ? 0.12 : 0.24).setFill()
    lowerGlow.fill()
}

func drawDocumentStack(in rect: CGRect, appearance: AppIconAppearance) {
    let scale = rect.width
    let backRect = CGRect(x: rect.minX + scale * 0.22, y: rect.minY + scale * 0.30, width: scale * 0.41, height: scale * 0.47)
    let middleRect = CGRect(x: rect.minX + scale * 0.285, y: rect.minY + scale * 0.245, width: scale * 0.41, height: scale * 0.49)
    let frontRect = CGRect(x: rect.minX + scale * 0.35, y: rect.minY + scale * 0.18, width: scale * 0.42, height: scale * 0.53)

    let backFill = appearance == .dark ? NSColor.white.withAlphaComponent(0.35) : NSColor.white.withAlphaComponent(0.60)
    let middleFill = appearance == .dark ? NSColor.white.withAlphaComponent(0.76) : NSColor.white.withAlphaComponent(0.86)
    let frontFill = appearance == .tinted ? NSColor(srgbRed: 0.98, green: 0.99, blue: 1.0, alpha: 1) : NSColor.white
    let line = appearance == .dark
        ? NSColor(srgbRed: 0.16, green: 0.32, blue: 0.34, alpha: 0.34)
        : NSColor(srgbRed: 0.14, green: 0.35, blue: 0.36, alpha: 0.16)

    drawDocument(at: backRect, angle: -12, fill: backFill, lineColor: line.withAlphaComponent(0.12))
    drawDocument(at: middleRect, angle: -4, fill: middleFill, lineColor: line.withAlphaComponent(0.18))
    drawDocument(at: frontRect, angle: 6, fill: frontFill, lineColor: line)
}

func drawDocument(at rect: CGRect, angle: CGFloat, fill: NSColor, lineColor: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.085, yRadius: rect.width * 0.085)
    let transform = NSAffineTransform()
    let center = CGPoint(x: rect.midX, y: rect.midY)

    NSGraphicsContext.saveGraphicsState()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: angle)
    transform.translateX(by: -center.x, yBy: -center.y)
    transform.concat()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.13)
    shadow.shadowBlurRadius = rect.width * 0.085
    shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.03)
    shadow.set()
    fill.setFill()
    path.fill()

    lineColor.setFill()
    for index in 0..<4 {
        let lineRect = CGRect(
            x: rect.minX + rect.width * 0.14,
            y: rect.maxY - rect.height * (0.24 + CGFloat(index) * 0.14),
            width: rect.width * (index == 0 ? 0.50 : 0.67),
            height: max(1.0, rect.height * 0.034)
        )
        NSBezierPath(roundedRect: lineRect, xRadius: lineRect.height / 2, yRadius: lineRect.height / 2).fill()
    }

    NSGraphicsContext.restoreGraphicsState()
}

func drawValueTag(in rect: CGRect, appearance: AppIconAppearance) {
    let scale = rect.width
    let tagRect = CGRect(x: rect.minX + scale * 0.57, y: rect.minY + scale * 0.54, width: scale * 0.225, height: scale * 0.17)
    let notch = tagRect.width * 0.28
    let tagPath = NSBezierPath()

    tagPath.move(to: CGPoint(x: tagRect.minX, y: tagRect.midY))
    tagPath.line(to: CGPoint(x: tagRect.minX + notch, y: tagRect.maxY))
    tagPath.line(to: CGPoint(x: tagRect.maxX, y: tagRect.maxY))
    tagPath.line(to: CGPoint(x: tagRect.maxX, y: tagRect.minY))
    tagPath.line(to: CGPoint(x: tagRect.minX + notch, y: tagRect.minY))
    tagPath.close()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.18)
    shadow.shadowBlurRadius = scale * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -scale * 0.01)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    tagColor(for: appearance).setFill()
    tagPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.92).setFill()
    let punchSize = max(1, scale * 0.018)
    NSBezierPath(ovalIn: CGRect(x: tagRect.minX + notch * 0.68, y: tagRect.midY - punchSize / 2, width: punchSize, height: punchSize)).fill()

    let barHeight = max(1, tagRect.height * 0.12)
    for index in 0..<2 {
        let width = tagRect.width * (index == 0 ? 0.34 : 0.25)
        let bar = CGRect(
            x: tagRect.maxX - tagRect.width * 0.47,
            y: tagRect.minY + tagRect.height * (0.36 + CGFloat(index) * 0.22),
            width: width,
            height: barHeight
        )
        NSBezierPath(roundedRect: bar, xRadius: barHeight / 2, yRadius: barHeight / 2).fill()
    }
}

func tagColor(for appearance: AppIconAppearance) -> NSColor {
    switch appearance {
    case .light: NSColor(srgbRed: 0.90, green: 0.29, blue: 0.22, alpha: 1)
    case .dark: NSColor(srgbRed: 1.00, green: 0.48, blue: 0.30, alpha: 1)
    case .tinted: NSColor(srgbRed: 0.42, green: 0.46, blue: 0.55, alpha: 1)
    }
}
