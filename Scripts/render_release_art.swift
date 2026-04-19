#!/usr/bin/env swift

import AppKit
import CoreText
import Foundation

enum RenderError: Error {
    case usage
    case bitmapCreationFailed
    case pngEncodingFailed
    case iconutilFailed
}

// MARK: - Palette
//
// Colors live as CGColor (sRGB). NSColor(srgbRed:).cgColor silently collapses
// dark colors toward grayscale in this pipeline, so we avoid NSColor for
// fills/strokes/gradients. `ns(...)` wraps to NSColor only where AppKit APIs
// require it (NSShadow, NSAttributedString attributes).

func cg(_ r: Int, _ g: Int, _ b: Int, alpha: CGFloat = 1) -> CGColor {
    CGColor(srgbRed: CGFloat(r) / 255.0, green: CGFloat(g) / 255.0, blue: CGFloat(b) / 255.0, alpha: alpha)
}

func cg(_ color: CGColor, alpha: CGFloat) -> CGColor {
    color.copy(alpha: alpha) ?? color
}

func ns(_ color: CGColor) -> NSColor {
    guard let comps = color.components, comps.count >= 3 else { return .black }
    let a: CGFloat = comps.count >= 4 ? comps[3] : 1
    return NSColor(srgbRed: comps[0], green: comps[1], blue: comps[2], alpha: a)
}

let neonCyan   = cg(  0, 230, 255)
let neonPurple = cg(192, 132, 255)
let neonPink   = cg(255,  79, 163)
let neonViolet = cg(123,  80, 255)
let neonBg     = cg( 10,   7,  22)
let neonInk    = cg(234, 243, 255)
let inkSoft    = cg(168, 158, 196)
let inkMuted   = cg(138, 130, 164)

let whiteA04 = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.04)
let whiteA05 = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.05)
let whiteA10 = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.10)
let whiteA14 = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.14)
let whiteA18 = CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.18)

let sRGBColorSpace = CGColorSpace(name: CGColorSpace.sRGB)!

// MARK: - Main

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

// MARK: - Rendering plumbing

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
    cgContext.clear(CGRect(x: 0, y: 0, width: width, height: height))
    draw(cgContext, CGSize(width: width, height: height))
    NSGraphicsContext.restoreGraphicsState()

    guard let data = rep.representation(using: .png, properties: [:]) else {
        throw RenderError.pngEncodingFailed
    }
    return data
}

// MARK: - Icon

func drawIcon(_ context: CGContext, _ size: CGSize) {
    let scale = size.width / 128
    let bodyRect = CGRect(x: 6 * scale, y: 6 * scale, width: 116 * scale, height: 116 * scale)
    let cornerRadius = 28 * scale

    // Drop shadow beneath the tile
    context.saveGState()
    context.setShadow(
        offset: CGSize(width: 0, height: -size.height * 0.02),
        blur: size.width * 0.06,
        color: CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.45)
    )
    context.setFillColor(CGColor(srgbRed: 0, green: 0, blue: 0, alpha: 0.35))
    addRoundedRect(context: context, rect: bodyRect, radius: cornerRadius)
    context.fillPath()
    context.restoreGState()

    // Body gradient + glows, clipped to the tile
    context.saveGState()
    addRoundedRect(context: context, rect: bodyRect, radius: cornerRadius)
    context.clip()

    drawLinearGradient(
        context: context,
        rect: bodyRect,
        colors: [cg(26, 16, 48), cg(7, 4, 20)],
        start: CGPoint(x: bodyRect.midX, y: bodyRect.maxY),
        end:   CGPoint(x: bodyRect.midX, y: bodyRect.minY)
    )

    drawRadialGlow(
        context: context,
        center: CGPoint(x: bodyRect.minX + bodyRect.width * 0.28, y: bodyRect.minY + bodyRect.height * 0.74),
        radius: bodyRect.width * 0.80,
        color: cg(neonViolet, alpha: 0.50)
    )
    drawRadialGlow(
        context: context,
        center: CGPoint(x: bodyRect.maxX - bodyRect.width * 0.20, y: bodyRect.minY + bodyRect.height * 0.28),
        radius: bodyRect.width * 0.55,
        color: cg(neonPink, alpha: 0.35)
    )

    // Inner ring
    let innerCircleRect = CGRect(x: 24 * scale, y: 24 * scale, width: 80 * scale, height: 80 * scale)
    context.setFillColor(whiteA04)
    context.fillEllipse(in: innerCircleRect)
    context.setStrokeColor(whiteA14)
    context.setLineWidth(max(0.5, 1 * scale))
    context.strokeEllipse(in: innerCircleRect)

    // Signal wave with gradient stroke (cyan → purple → pink).
    // SVG path M24 68 Q40 44 64 64 T104 60, y-flipped into CoreGraphics bottom-up coords.
    let wavePath = CGMutablePath()
    wavePath.move(to: CGPoint(x: 24 * scale, y: 60 * scale))
    wavePath.addQuadCurve(
        to: CGPoint(x: 64 * scale, y: 64 * scale),
        control: CGPoint(x: 40 * scale, y: 84 * scale)
    )
    wavePath.addQuadCurve(
        to: CGPoint(x: 104 * scale, y: 68 * scale),
        control: CGPoint(x: 88 * scale, y: 44 * scale)
    )

    let waveWidth = max(1, 5 * scale)
    strokeGradient(
        context: context,
        path: wavePath,
        lineWidth: waveWidth,
        start: CGPoint(x: 24 * scale, y: 64 * scale),
        end:   CGPoint(x: 104 * scale, y: 64 * scale),
        colors: [neonCyan, neonPurple, neonPink]
    )

    // Endpoint dots (only draw when big enough to register)
    if scale >= 0.75 {
        context.setFillColor(neonPink)
        context.fillEllipse(in: dotRect(center: CGPoint(x: 104 * scale, y: 68 * scale), radius: 4.5 * scale))
        context.setFillColor(neonCyan)
        context.fillEllipse(in: dotRect(center: CGPoint(x: 24 * scale, y: 60 * scale), radius: 3.5 * scale))
    }

    context.restoreGState()

    // Hairline border on top
    context.setStrokeColor(CGColor(srgbRed: 1, green: 1, blue: 1, alpha: 0.09))
    context.setLineWidth(max(0.5, 1 * scale))
    addRoundedRect(context: context, rect: bodyRect, radius: cornerRadius)
    context.strokePath()
}

// MARK: - DMG background

func drawDMGBackground(_ context: CGContext, _ size: CGSize) {
    let rect = CGRect(origin: .zero, size: size)

    // Base dark violet
    context.setFillColor(neonBg)
    context.fill(rect)

    // Three big radial glows to create the neon wash
    drawRadialGlow(context: context, center: CGPoint(x: 140, y: 320), radius: 380,
                   color: cg(neonViolet, alpha: 0.85))
    drawRadialGlow(context: context, center: CGPoint(x: 600, y: 110), radius: 340,
                   color: cg(neonCyan, alpha: 0.65))
    drawRadialGlow(context: context, center: CGPoint(x: 360, y: -60), radius: 500,
                   color: cg(neonPink, alpha: 0.45))

    // Subtle 40px grid
    context.saveGState()
    context.setStrokeColor(whiteA05)
    context.setLineWidth(1)
    for x in stride(from: CGFloat(0), through: size.width, by: 40) {
        context.move(to: CGPoint(x: x, y: 0))
        context.addLine(to: CGPoint(x: x, y: size.height))
    }
    for y in stride(from: CGFloat(0), through: size.height, by: 40) {
        context.move(to: CGPoint(x: 0, y: y))
        context.addLine(to: CGPoint(x: size.width, y: y))
    }
    context.strokePath()
    context.restoreGState()

    // Brand header: "QUOTABAR" in a cyan→purple→pink gradient
    drawGradientText(
        context: context,
        string: "QUOTABAR",
        font: NSFont.systemFont(ofSize: 26, weight: .heavy),
        tracking: 6,
        center: CGPoint(x: size.width / 2, y: size.height - 44),
        gradientColors: [neonCyan, neonPurple, neonPink]
    )

    // Subtitle
    let subtitle = NSAttributedString(
        string: "DROP · TO · INSTALL",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: ns(inkSoft),
            .kern: NSNumber(value: 3.2),
        ]
    )
    let subtitleSize = subtitle.size()
    subtitle.draw(at: CGPoint(x: (size.width - subtitleSize.width) / 2, y: size.height - 72))

    // Finder places the two icons at {180, 235} and {520, 235} in top-left-origin coords
    // with icon size 128. Bottom-up: centers at y = 440 - 235 = 205. The label sits
    // below the icon (~15-20px in Finder units), so the cells are taller than wide
    // and their centers nudged down so the whole icon+label block is enclosed.
    let cellWidth: CGFloat = 184
    let cellHeight: CGFloat = 208
    let cellCenterY: CGFloat = 188       // shifts cell down to include label band
    let leftCellCenter  = CGPoint(x: 180, y: cellCenterY)
    let rightCellCenter = CGPoint(x: 520, y: cellCenterY)
    drawNeonCell(context: context, center: leftCellCenter,
                 width: cellWidth, height: cellHeight, accent: neonCyan)
    drawNeonCell(context: context, center: rightCellCenter,
                 width: cellWidth, height: cellHeight, accent: neonPink)

    // Arrow + drag pill — aim at icon height (not the taller cell's center)
    let arrowY: CGFloat = 205
    drawNeonArrow(
        context: context,
        from: CGPoint(x: leftCellCenter.x  + cellWidth / 2 + 10, y: arrowY),
        to:   CGPoint(x: rightCellCenter.x - cellWidth / 2 - 10, y: arrowY)
    )
    drawDragBadge(
        context: context,
        center: CGPoint(x: (leftCellCenter.x + rightCellCenter.x) / 2, y: arrowY + 30),
        accent: neonCyan
    )

    // Footer
    let foot = NSAttributedString(
        string: "macOS 13+  ·  universal · signed & notarized  ·  menu-bar only, no dock icon",
        attributes: [
            .font: NSFont.systemFont(ofSize: 11, weight: .regular),
            .foregroundColor: ns(inkMuted),
            .kern: NSNumber(value: 0.4),
        ]
    )
    let footSize = foot.size()
    foot.draw(at: CGPoint(x: (size.width - footSize.width) / 2, y: 22))
}

// MARK: - Neon primitives

func drawNeonCell(context: CGContext, center: CGPoint, width: CGFloat, height: CGFloat, accent: CGColor) {
    let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)

    // Glass fill
    context.saveGState()
    addRoundedRect(context: context, rect: rect, radius: 26)
    context.clip()
    drawLinearGradient(
        context: context,
        rect: rect,
        colors: [whiteA10, whiteA04],
        start: CGPoint(x: rect.minX, y: rect.maxY),
        end:   CGPoint(x: rect.maxX, y: rect.minY)
    )
    context.restoreGState()

    // Soft accent glow behind the border stroke
    context.saveGState()
    context.setShadow(offset: .zero, blur: 24, color: cg(accent, alpha: 0.55))
    context.setStrokeColor(whiteA18)
    context.setLineWidth(1)
    addRoundedRect(context: context, rect: rect, radius: 26)
    context.strokePath()
    context.restoreGState()

    // Corner brackets (top-left + bottom-right)
    let arm: CGFloat = 16
    context.saveGState()
    context.setStrokeColor(accent)
    context.setLineWidth(2)
    context.setLineCap(.round)

    // Top-left bracket (top = high y in bottom-up space)
    context.move(to: CGPoint(x: rect.minX, y: rect.maxY - arm))
    context.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    context.addLine(to: CGPoint(x: rect.minX + arm, y: rect.maxY))

    // Bottom-right bracket
    context.move(to: CGPoint(x: rect.maxX, y: rect.minY + arm))
    context.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
    context.addLine(to: CGPoint(x: rect.maxX - arm, y: rect.minY))

    context.strokePath()
    context.restoreGState()
}

func drawNeonArrow(context: CGContext, from start: CGPoint, to end: CGPoint) {
    let path = CGMutablePath()
    path.move(to: start)
    path.addLine(to: end)

    // Soft glow underlay
    strokeGradient(
        context: context,
        path: path,
        lineWidth: 5,
        start: start, end: end,
        colors: [cg(neonCyan, alpha: 0.45), cg(neonPink, alpha: 0.45)]
    )
    // Crisp gradient core
    strokeGradient(
        context: context,
        path: path,
        lineWidth: 1.8,
        start: start, end: end,
        colors: [neonCyan, neonPink]
    )

    // Arrowhead (pink chevron)
    context.saveGState()
    context.setStrokeColor(neonPink)
    context.setLineWidth(2.2)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.move(to: CGPoint(x: end.x - 11, y: end.y + 9))
    context.addLine(to: end)
    context.addLine(to: CGPoint(x: end.x - 11, y: end.y - 9))
    context.strokePath()
    context.restoreGState()
}

func drawDragBadge(context: CGContext, center: CGPoint, accent: CGColor) {
    let attr = NSAttributedString(
        string: "DRAG  →",
        attributes: [
            .font: NSFont.monospacedSystemFont(ofSize: 10, weight: .bold),
            .foregroundColor: ns(neonInk),
            .kern: NSNumber(value: 3.0),
        ]
    )
    let textSize = attr.size()
    let padX: CGFloat = 12
    let height: CGFloat = 22
    let width = textSize.width + padX * 2
    let rect = CGRect(x: center.x - width / 2, y: center.y - height / 2, width: width, height: height)

    // Accent glow behind the pill
    context.saveGState()
    context.setShadow(offset: .zero, blur: 16, color: cg(accent, alpha: 0.65))
    context.setFillColor(cg(accent, alpha: 0.14))
    addRoundedRect(context: context, rect: rect, radius: 7)
    context.fillPath()
    context.restoreGState()

    // Border
    context.setStrokeColor(cg(accent, alpha: 0.8))
    context.setLineWidth(1)
    addRoundedRect(context: context, rect: rect, radius: 7)
    context.strokePath()

    // Text
    attr.draw(at: CGPoint(x: rect.minX + padX, y: rect.midY - textSize.height / 2 + 1))
}

// MARK: - Gradient / shape helpers

func drawRadialGlow(context: CGContext, center: CGPoint, radius: CGFloat, color: CGColor) {
    let colors = [color, cg(color, alpha: 0)] as CFArray
    guard let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: colors, locations: [0, 1]) else { return }
    context.drawRadialGradient(
        grad,
        startCenter: center, startRadius: 0,
        endCenter: center,   endRadius: radius,
        options: []
    )
}

func drawLinearGradient(
    context: CGContext,
    rect: CGRect,
    colors: [CGColor],
    start: CGPoint,
    end: CGPoint
) {
    guard let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: colors as CFArray, locations: nil) else { return }
    context.saveGState()
    context.clip(to: rect)
    context.drawLinearGradient(grad, start: start, end: end,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func strokeGradient(
    context: CGContext,
    path: CGPath,
    lineWidth: CGFloat,
    start: CGPoint,
    end: CGPoint,
    colors: [CGColor]
) {
    guard let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: colors as CFArray, locations: nil) else { return }
    context.saveGState()
    context.addPath(path)
    context.setLineWidth(lineWidth)
    context.setLineCap(.round)
    context.setLineJoin(.round)
    context.replacePathWithStrokedPath()
    context.clip()
    context.drawLinearGradient(grad, start: start, end: end,
                               options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
    context.restoreGState()
}

func drawGradientText(
    context: CGContext,
    string: String,
    font: NSFont,
    tracking: CGFloat,
    center: CGPoint,
    gradientColors: [CGColor]
) {
    let attr = NSAttributedString(
        string: string,
        attributes: [
            .font: font,
            .foregroundColor: NSColor.white,
            .kern: NSNumber(value: Double(tracking)),
        ]
    )
    let line = CTLineCreateWithAttributedString(attr)
    let bounds = CTLineGetBoundsWithOptions(line, [])
    let baseX = center.x - bounds.midX
    let baseY = center.y - bounds.midY

    let glyphPath = CGMutablePath()
    let runs = CTLineGetGlyphRuns(line) as! [CTRun]
    for run in runs {
        let glyphCount = CTRunGetGlyphCount(run)
        guard glyphCount > 0 else { continue }
        let attrs = CTRunGetAttributes(run) as NSDictionary
        guard let runFont = attrs[kCTFontAttributeName as String] else { continue }
        let ctFont = runFont as! CTFont
        var glyphs = [CGGlyph](repeating: 0, count: glyphCount)
        var positions = [CGPoint](repeating: .zero, count: glyphCount)
        CTRunGetGlyphs(run, CFRange(location: 0, length: glyphCount), &glyphs)
        CTRunGetPositions(run, CFRange(location: 0, length: glyphCount), &positions)
        for i in 0..<glyphCount {
            guard let gp = CTFontCreatePathForGlyph(ctFont, glyphs[i], nil) else { continue }
            let t = CGAffineTransform(translationX: baseX + positions[i].x, y: baseY + positions[i].y)
            glyphPath.addPath(gp, transform: t)
        }
    }

    guard let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB),
                                colors: gradientColors as CFArray, locations: nil) else { return }

    context.saveGState()
    context.addPath(glyphPath)
    context.clip()
    context.drawLinearGradient(
        grad,
        start: CGPoint(x: baseX + bounds.minX, y: center.y),
        end:   CGPoint(x: baseX + bounds.maxX, y: center.y),
        options: [.drawsBeforeStartLocation, .drawsAfterEndLocation]
    )
    context.restoreGState()
}

// MARK: - Small helpers

func addRoundedRect(context: CGContext, rect: CGRect, radius: CGFloat) {
    let path = CGPath(roundedRect: rect, cornerWidth: radius, cornerHeight: radius, transform: nil)
    context.addPath(path)
}

func dotRect(center: CGPoint, radius: CGFloat) -> CGRect {
    CGRect(x: center.x - radius, y: center.y - radius, width: radius * 2, height: radius * 2)
}
