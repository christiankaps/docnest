import AppKit
import Foundation

struct IconSpec {
    let filename: String
    let pixels: Int
}

let outputDirectory = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("DocNest/Resources/Assets.xcassets/AppIcon.appiconset", isDirectory: true)

let iconSpecs = [
    IconSpec(filename: "icon_16x16.png", pixels: 16),
    IconSpec(filename: "icon_16x16@2x.png", pixels: 32),
    IconSpec(filename: "icon_32x32.png", pixels: 32),
    IconSpec(filename: "icon_32x32@2x.png", pixels: 64),
    IconSpec(filename: "icon_128x128.png", pixels: 128),
    IconSpec(filename: "icon_128x128@2x.png", pixels: 256),
    IconSpec(filename: "icon_256x256.png", pixels: 256),
    IconSpec(filename: "icon_256x256@2x.png", pixels: 512),
    IconSpec(filename: "icon_512x512.png", pixels: 512),
    IconSpec(filename: "icon_512x512@2x.png", pixels: 1024)
]

try FileManager.default.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

for spec in iconSpecs {
    let image = NSImage(size: NSSize(width: spec.pixels, height: spec.pixels), flipped: false) { rect in
        drawIcon(in: rect)
        return true
    }

    guard
        let tiff = image.tiffRepresentation,
        let bitmap = NSBitmapImageRep(data: tiff),
        let pngData = bitmap.representation(using: .png, properties: [:])
    else {
        throw NSError(domain: "DocNestIconGenerator", code: 1)
    }

    let fileURL = outputDirectory.appendingPathComponent(spec.filename)
    try pngData.write(to: fileURL)
}

func drawIcon(in rect: CGRect) {
    let insetRect = rect.insetBy(dx: rect.width * 0.06, dy: rect.height * 0.06)
    let cornerRadius = insetRect.width * 0.23
    let backgroundPath = NSBezierPath(roundedRect: insetRect, xRadius: cornerRadius, yRadius: cornerRadius)

    NSGraphicsContext.current?.imageInterpolation = .high

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.18)
    shadow.shadowBlurRadius = rect.width * 0.05
    shadow.shadowOffset = NSSize(width: 0, height: -rect.height * 0.018)
    shadow.set()

    let gradient = NSGradient(colors: [
        NSColor(srgbRed: 0.08, green: 0.34, blue: 0.33, alpha: 1.0),
        NSColor(srgbRed: 0.07, green: 0.63, blue: 0.53, alpha: 1.0),
        NSColor(srgbRed: 0.98, green: 0.75, blue: 0.35, alpha: 1.0)
    ])
    gradient?.draw(in: backgroundPath, angle: -55)

    NSGraphicsContext.saveGraphicsState()
    backgroundPath.addClip()
    drawAtmosphere(in: insetRect)
    drawDocumentStack(in: insetRect)
    drawLabelTag(in: insetRect)
    NSGraphicsContext.restoreGraphicsState()

    NSColor.white.withAlphaComponent(0.12).setStroke()
    backgroundPath.lineWidth = max(1, rect.width * 0.01)
    backgroundPath.stroke()
}

func drawAtmosphere(in rect: CGRect) {
    let glowA = NSBezierPath(ovalIn: CGRect(x: rect.minX - rect.width * 0.2, y: rect.maxY - rect.height * 0.46, width: rect.width * 0.62, height: rect.height * 0.48))
    NSColor.white.withAlphaComponent(0.15).setFill()
    glowA.fill()

    let glowB = NSBezierPath(ovalIn: CGRect(x: rect.maxX - rect.width * 0.54, y: rect.minY + rect.height * 0.02, width: rect.width * 0.6, height: rect.height * 0.42))
    NSColor(srgbRed: 0.98, green: 0.92, blue: 0.72, alpha: 0.22).setFill()
    glowB.fill()
}

func drawDocumentStack(in rect: CGRect) {
    let scale = rect.width
    let backRect = CGRect(x: rect.minX + scale * 0.23, y: rect.minY + scale * 0.29, width: scale * 0.41, height: scale * 0.48)
    let middleRect = CGRect(x: rect.minX + scale * 0.29, y: rect.minY + scale * 0.24, width: scale * 0.41, height: scale * 0.5)
    let frontRect = CGRect(x: rect.minX + scale * 0.35, y: rect.minY + scale * 0.19, width: scale * 0.42, height: scale * 0.52)

    drawDocument(at: backRect, angle: -12, fill: NSColor.white.withAlphaComponent(0.52), lineColor: NSColor.white.withAlphaComponent(0.25))
    drawDocument(at: middleRect, angle: -4, fill: NSColor.white.withAlphaComponent(0.78), lineColor: NSColor(srgbRed: 0.22, green: 0.45, blue: 0.44, alpha: 0.18))
    drawDocument(at: frontRect, angle: 6, fill: NSColor.white, lineColor: NSColor(srgbRed: 0.18, green: 0.31, blue: 0.31, alpha: 0.12))
}

func drawDocument(at rect: CGRect, angle: CGFloat, fill: NSColor, lineColor: NSColor) {
    let path = NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.08, yRadius: rect.width * 0.08)

    let transform = NSAffineTransform()
    let center = CGPoint(x: rect.midX, y: rect.midY)
    NSGraphicsContext.saveGraphicsState()
    transform.translateX(by: center.x, yBy: center.y)
    transform.rotate(byDegrees: angle)
    transform.translateX(by: -center.x, yBy: -center.y)
    transform.concat()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.12)
    shadow.shadowBlurRadius = rect.width * 0.08
    shadow.shadowOffset = NSSize(width: 0, height: -rect.width * 0.03)
    shadow.set()
    fill.setFill()
    path.fill()

    NSGraphicsContext.restoreGraphicsState()
    NSGraphicsContext.saveGraphicsState()
    transform.concat()

    lineColor.setFill()
    for index in 0..<4 {
        let lineRect = CGRect(
            x: rect.minX + rect.width * 0.14,
            y: rect.maxY - rect.height * (0.24 + CGFloat(index) * 0.14),
            width: rect.width * (index == 0 ? 0.54 : 0.68),
            height: max(1.0, rect.height * 0.035)
        )
        let line = NSBezierPath(roundedRect: lineRect, xRadius: lineRect.height / 2, yRadius: lineRect.height / 2)
        line.fill()
    }

    NSGraphicsContext.restoreGraphicsState()
}

func drawLabelTag(in rect: CGRect) {
    let scale = rect.width
    let tagRect = CGRect(x: rect.minX + scale * 0.58, y: rect.minY + scale * 0.54, width: scale * 0.21, height: scale * 0.16)
    let tagPath = NSBezierPath()
    let notch = tagRect.width * 0.28

    tagPath.move(to: CGPoint(x: tagRect.minX, y: tagRect.midY))
    tagPath.line(to: CGPoint(x: tagRect.minX + notch, y: tagRect.maxY))
    tagPath.line(to: CGPoint(x: tagRect.maxX, y: tagRect.maxY))
    tagPath.line(to: CGPoint(x: tagRect.maxX, y: tagRect.minY))
    tagPath.line(to: CGPoint(x: tagRect.minX + notch, y: tagRect.minY))
    tagPath.close()

    let shadow = NSShadow()
    shadow.shadowColor = NSColor(calibratedWhite: 0.0, alpha: 0.16)
    shadow.shadowBlurRadius = scale * 0.03
    shadow.shadowOffset = NSSize(width: 0, height: -scale * 0.01)

    NSGraphicsContext.saveGraphicsState()
    shadow.set()
    NSColor(srgbRed: 0.95, green: 0.35, blue: 0.24, alpha: 1.0).setFill()
    tagPath.fill()
    NSGraphicsContext.restoreGraphicsState()

    let punchSize = scale * 0.018
    let punchRect = CGRect(x: tagRect.minX + notch * 0.7, y: tagRect.midY - punchSize / 2, width: punchSize, height: punchSize)
    let punch = NSBezierPath(ovalIn: punchRect)
    NSColor.white.withAlphaComponent(0.9).setFill()
    punch.fill()
}