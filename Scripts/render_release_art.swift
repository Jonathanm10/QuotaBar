#!/usr/bin/env swift

import AppKit
import Foundation

enum RenderError: Error {
    case usage
    case bitmapCreationFailed
    case pngEncodingFailed
    case iconutilFailed
}

let arguments = CommandLine.arguments
guard arguments.count == 2 else {
    FileHandle.standardError.write(Data("usage: render_release_art.swift <output-dir>\n".utf8))
    throw RenderError.usage
}

let outputDirectory = URL(fileURLWithPath: arguments[1], isDirectory: true)
let fileManager = FileManager.default
try fileManager.createDirectory(at: outputDirectory, withIntermediateDirectories: true)

let iconsetDirectory = outputDirectory.appendingPathComponent("QuotaBar.iconset", isDirectory: true)
try? fileManager.removeItem(at: iconsetDirectory)
try fileManager.createDirectory(at: iconsetDirectory, withIntermediateDirectories: true)

let iconOutputs: [(name: String, pixels: Int)] = [
    ("icon_16x16.png", 16),
    ("icon_16x16@2x.png", 32),
    ("icon_32x32.png", 32),
    ("icon_32x32@2x.png", 64),
    ("icon_128x128.png", 128),
    ("icon_128x128@2x.png", 256),
    ("icon_256x256.png", 256),
    ("icon_256x256@2x.png", 512),
    ("icon_512x512.png", 512),
    ("icon_512x512@2x.png", 1024),
]

for output in iconOutputs {
    let data = try renderPNG(width: output.pixels, height: output.pixels, draw: drawIcon)
    try data.write(to: iconsetDirectory.appendingPathComponent(output.name))
}

let iconutil = Process()
iconutil.executableURL = URL(fileURLWithPath: "/usr/bin/iconutil")
iconutil.arguments = [
    "-c", "icns",
    iconsetDirectory.path,
    "-o", outputDirectory.appendingPathComponent("QuotaBar.icns").path,
]
try iconutil.run()
iconutil.waitUntilExit()
guard iconutil.terminationStatus == 0 else {
    throw RenderError.iconutilFailed
}

let background = try renderPNG(width: 720, height: 440, draw: drawDMGBackground)
try background.write(to: outputDirectory.appendingPathComponent("dmg-background.png"))

func renderPNG(width: Int, height: Int, draw: (CGContext, CGSize) -> Void) throws -> Data {
    guard
        let rep = NSBitmapImageRep(
            bitmapDataPlanes: nil,
            pixelsWide: width,
            pixelsHigh: height,
            bitsPerSample: 8,
            samplesPerPixel: 4,
            hasAlpha: true,
            isPlanar: false,
            colorSpaceName: .deviceRGB,
            bytesPerRow: 0,
            bitsPerPixel: 0
        ),
        let context = NSGraphicsContext(bitmapImageRep: rep)
    else {
        throw RenderError.bitmapCreationFailed
    }

    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    let cgContext = context.cgContext
    cgContext.setFillColor(NSColor.clear.cgColor)
    cgContext.fill(CGRect(x: 0, y: 0, width: width, height: height))
    draw(cgContext, CGSize(width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw RenderError.pngEncodingFailed
    }
    return data
}

func drawIcon(_ context: CGContext, _ size: CGSize) {
    let rect = CGRect(origin: .zero, size: size)
    let radius = size.width * 0.22

    context.saveGState()
    let shadow = NSShadow()
    shadow.shadowBlurRadius = size.width * 0.06
    shadow.shadowOffset = CGSize(width: 0, height: -size.height * 0.02)
    shadow.shadowColor = NSColor(calibratedWhite: 0, alpha: 0.34)
    shadow.set()
    NSColor(calibratedWhite: 0, alpha: 0.42).setFill()
    roundedRect(rect.insetBy(dx: size.width * 0.04, dy: size.height * 0.04), radius: radius).fill()
    context.restoreGState()

    let cardRect = rect.insetBy(dx: size.width * 0.06, dy: size.height * 0.06)
    let card = roundedRect(cardRect, radius: radius)
    card.addClip()

    NSGradient(colors: [
        NSColor(red: 18 / 255, green: 28 / 255, blue: 41 / 255, alpha: 1),
        NSColor(red: 10 / 255, green: 15 / 255, blue: 24 / 255, alpha: 1),
    ])?.draw(in: cardRect, angle: 255)

    let haloRect = CGRect(
        x: cardRect.minX - size.width * 0.18,
        y: cardRect.midY - size.height * 0.08,
        width: size.width * 0.8,
        height: size.height * 0.65
    )
    NSColor(red: 71 / 255, green: 214 / 255, blue: 170 / 255, alpha: 0.16).setFill()
    NSBezierPath(ovalIn: haloRect).fill()

    let glowRect = CGRect(
        x: cardRect.midX - size.width * 0.12,
        y: cardRect.minY + size.height * 0.08,
        width: size.width * 0.62,
        height: size.height * 0.62
    )
    NSColor(red: 255 / 255, green: 159 / 255, blue: 67 / 255, alpha: 0.12).setFill()
    NSBezierPath(ovalIn: glowRect).fill()

    let ringLineWidth = size.width * 0.085
    let ringRect = CGRect(
        x: size.width * 0.2,
        y: size.height * 0.21,
        width: size.width * 0.6,
        height: size.height * 0.6
    )

    strokeArc(in: ringRect, startAngle: 135, endAngle: 244, lineWidth: ringLineWidth, color: NSColor(red: 77 / 255, green: 234 / 255, blue: 190 / 255, alpha: 1))
    strokeArc(in: ringRect, startAngle: 252, endAngle: 309, lineWidth: ringLineWidth, color: NSColor(red: 239 / 255, green: 246 / 255, blue: 255 / 255, alpha: 0.96))
    strokeArc(in: ringRect, startAngle: 318, endAngle: 395, lineWidth: ringLineWidth, color: NSColor(red: 255 / 255, green: 166 / 255, blue: 84 / 255, alpha: 1))

    let tailRect = CGRect(
        x: size.width * 0.62,
        y: size.height * 0.24,
        width: size.width * 0.14,
        height: size.height * 0.18
    )
    context.saveGState()
    context.translateBy(x: tailRect.midX, y: tailRect.midY)
    context.rotate(by: -.pi / 4.4)
    let tail = roundedRect(
        CGRect(x: -tailRect.width / 2, y: -tailRect.height / 2, width: tailRect.width, height: tailRect.height),
        radius: tailRect.width * 0.32
    )
    NSColor(red: 239 / 255, green: 246 / 255, blue: 255 / 255, alpha: 0.94).setFill()
    tail.fill()
    context.restoreGState()

    let chipWidth = size.width * 0.12
    let chipHeight = size.height * 0.03
    NSColor.white.withAlphaComponent(0.08).setFill()
    roundedRect(CGRect(x: size.width * 0.21, y: size.height * 0.72, width: chipWidth, height: chipHeight), radius: chipHeight / 2).fill()
    NSColor(red: 77 / 255, green: 234 / 255, blue: 190 / 255, alpha: 1).setFill()
    roundedRect(CGRect(x: size.width * 0.21, y: size.height * 0.67, width: chipWidth * 1.6, height: chipHeight), radius: chipHeight / 2).fill()
    NSColor(red: 255 / 255, green: 166 / 255, blue: 84 / 255, alpha: 1).setFill()
    roundedRect(CGRect(x: size.width * 0.21, y: size.height * 0.62, width: chipWidth * 1.25, height: chipHeight), radius: chipHeight / 2).fill()

    card.lineWidth = max(2, size.width * 0.01)
    NSColor.white.withAlphaComponent(0.08).setStroke()
    card.stroke()
}

func drawDMGBackground(_ context: CGContext, _ size: CGSize) {
    let rect = CGRect(origin: .zero, size: size)
    NSGradient(colors: [
        NSColor(red: 6 / 255, green: 11 / 255, blue: 18 / 255, alpha: 1),
        NSColor(red: 14 / 255, green: 21 / 255, blue: 33 / 255, alpha: 1),
    ])?.draw(in: rect, angle: 0)

    NSColor.white.withAlphaComponent(0.03).setFill()
    NSBezierPath(ovalIn: CGRect(x: -120, y: 180, width: 300, height: 300)).fill()
    NSColor(red: 77 / 255, green: 234 / 255, blue: 190 / 255, alpha: 0.07).setFill()
    NSBezierPath(ovalIn: CGRect(x: 20, y: 90, width: 320, height: 320)).fill()
    NSColor(red: 255 / 255, green: 166 / 255, blue: 84 / 255, alpha: 0.08).setFill()
    NSBezierPath(ovalIn: CGRect(x: 440, y: 20, width: 260, height: 260)).fill()

    let iconInset = CGRect(x: 52, y: 117, width: 138, height: 138)
    if let iconData = try? renderPNG(width: 1024, height: 1024, draw: drawIcon),
       let image = NSImage(data: iconData) {
        image.draw(in: iconInset)
    }

    let title = NSAttributedString(
        string: "QuotaBar",
        attributes: [
            .font: NSFont.systemFont(ofSize: 39, weight: .semibold),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.97),
        ]
    )
    title.draw(at: CGPoint(x: 218, y: 274))

    let subtitle = NSAttributedString(
        string: "Track OpenAI and Anthropic budget from your menu bar.",
        attributes: [
            .font: NSFont.systemFont(ofSize: 17, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.72),
        ]
    )
    subtitle.draw(at: CGPoint(x: 220, y: 235))

    let instruction = NSAttributedString(
        string: "Drag QuotaBar into Applications to install.",
        attributes: [
            .font: NSFont.systemFont(ofSize: 20, weight: .medium),
            .foregroundColor: NSColor(red: 239 / 255, green: 246 / 255, blue: 255 / 255, alpha: 0.96),
        ]
    )
    instruction.draw(at: CGPoint(x: 56, y: 40))

    let detail = NSAttributedString(
        string: "Menu bar app. Signed release. No extra setup required.",
        attributes: [
            .font: NSFont.systemFont(ofSize: 13, weight: .regular),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.55),
        ]
    )
    detail.draw(at: CGPoint(x: 58, y: 18))

    let arrow = NSBezierPath()
    arrow.move(to: CGPoint(x: 258, y: 214))
    arrow.curve(
        to: CGPoint(x: 520, y: 214),
        controlPoint1: CGPoint(x: 330, y: 250),
        controlPoint2: CGPoint(x: 430, y: 250)
    )
    arrow.lineWidth = 7
    arrow.lineCapStyle = .round
    NSColor(red: 239 / 255, green: 246 / 255, blue: 255 / 255, alpha: 0.68).setStroke()
    arrow.stroke()

    let arrowHead = NSBezierPath()
    arrowHead.move(to: CGPoint(x: 510, y: 228))
    arrowHead.line(to: CGPoint(x: 540, y: 214))
    arrowHead.line(to: CGPoint(x: 510, y: 200))
    arrowHead.lineWidth = 7
    arrowHead.lineCapStyle = .round
    arrowHead.lineJoinStyle = .round
    arrowHead.stroke()

    let appLabel = badge(text: "QuotaBar.app", width: 122)
    appLabel.draw(
        in: CGRect(x: 117, y: 337, width: 122, height: 30),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )

    let appsLabel = badge(text: "Applications", width: 124)
    appsLabel.draw(
        in: CGRect(x: 458, y: 337, width: 124, height: 30),
        from: .zero,
        operation: .sourceOver,
        fraction: 1
    )
}

func badge(text: String, width: CGFloat) -> NSImage {
    let size = CGSize(width: width, height: 30)
    let image = NSImage(size: size)
    image.lockFocus()
    let rect = CGRect(origin: .zero, size: size)
    NSColor.white.withAlphaComponent(0.08).setFill()
    roundedRect(rect, radius: 15).fill()
    let textRect = rect.insetBy(dx: 12, dy: 6)
    let attr = NSAttributedString(
        string: text,
        attributes: [
            .font: NSFont.systemFont(ofSize: 12, weight: .medium),
            .foregroundColor: NSColor(calibratedWhite: 1, alpha: 0.85),
        ]
    )
    attr.draw(in: textRect)
    image.unlockFocus()
    return image
}

func roundedRect(_ rect: CGRect, radius: CGFloat) -> NSBezierPath {
    NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius)
}

func strokeArc(in rect: CGRect, startAngle: CGFloat, endAngle: CGFloat, lineWidth: CGFloat, color: NSColor) {
    let path = NSBezierPath()
    path.appendArc(withCenter: CGPoint(x: rect.midX, y: rect.midY), radius: rect.width / 2, startAngle: startAngle, endAngle: endAngle)
    path.lineWidth = lineWidth
    path.lineCapStyle = .round
    color.setStroke()
    path.stroke()
}
