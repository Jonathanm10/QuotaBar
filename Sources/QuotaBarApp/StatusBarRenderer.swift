import AppKit
import QuotaBarCore

enum StatusBarRenderer {
    static func render(snapshots: [ProviderSnapshot]) -> NSImage {
        let height: CGFloat = 18
        let logoSize: CGFloat = 13
        let logoTextSpacing: CGFloat = 4
        let groupSpacing: CGFloat = 10
        let font = NSFont.monospacedDigitSystemFont(
            ofSize: NSFont.systemFontSize(for: .small) + 0.5,
            weight: .medium
        )
        let textAttributes: [NSAttributedString.Key: Any] = [
            .font: font,
            .foregroundColor: NSColor.black,
        ]

        guard !snapshots.isEmpty else {
            return textImage("QuotaBar", attributes: textAttributes, height: height)
        }

        let tokens: [(NSImage, NSAttributedString)] = snapshots.map { snapshot in
            let logo = BrandLogos.nsImage(for: snapshot.provider)
            let string = NSAttributedString(
                string: Formatting.compactUsage(snapshot),
                attributes: textAttributes
            )
            return (logo, string)
        }

        var width: CGFloat = 0
        for (index, (_, text)) in tokens.enumerated() {
            if index > 0 { width += groupSpacing }
            width += logoSize + logoTextSpacing + text.size().width
        }
        width += 2

        let image = NSImage(size: NSSize(width: width, height: height), flipped: false) { _ in
            var x: CGFloat = 0
            for (index, (logo, text)) in tokens.enumerated() {
                if index > 0 { x += groupSpacing }
                let logoRect = NSRect(
                    x: x,
                    y: (height - logoSize) / 2,
                    width: logoSize,
                    height: logoSize
                )
                logo.draw(in: logoRect)
                x += logoSize + logoTextSpacing
                let textHeight = text.size().height
                text.draw(at: NSPoint(x: x, y: (height - textHeight) / 2))
                x += text.size().width
            }
            return true
        }
        image.isTemplate = true
        return image
    }

    private static func textImage(
        _ string: String,
        attributes: [NSAttributedString.Key: Any],
        height: CGFloat
    ) -> NSImage {
        let attr = NSAttributedString(string: string, attributes: attributes)
        let size = attr.size()
        let image = NSImage(size: NSSize(width: size.width + 4, height: height), flipped: false) { _ in
            attr.draw(at: NSPoint(x: 2, y: (height - size.height) / 2))
            return true
        }
        image.isTemplate = true
        return image
    }
}
