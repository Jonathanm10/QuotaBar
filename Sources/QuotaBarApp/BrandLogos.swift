import AppKit
import SwiftUI
import QuotaBarCore

enum BrandLogos {
    static let openAI: NSImage = load("openai")
    static let anthropic: NSImage = load("anthropic")

    static func nsImage(for provider: ProviderID) -> NSImage {
        switch provider {
        case .openAI: openAI
        case .anthropic: anthropic
        }
    }

    private static func load(_ name: String) -> NSImage {
        guard
            let url = Bundle.module.url(forResource: name, withExtension: "svg"),
            let image = NSImage(contentsOf: url)
        else {
            return NSImage(size: NSSize(width: 16, height: 16))
        }
        image.isTemplate = true
        return image
    }
}

struct BrandLogoView: View {
    let provider: ProviderID
    var size: CGFloat = 16

    var body: some View {
        Image(nsImage: BrandLogos.nsImage(for: provider))
            .resizable()
            .renderingMode(.template)
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: size, height: size)
    }
}
