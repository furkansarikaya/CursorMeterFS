import AppKit

/// Cached loader for the bundled provider brand icons (template SVGs in
/// Resources/ProviderIcons/). Template rendering tints them to match the UI.
@MainActor
enum ProviderBrandIcon {
    private static let size = NSSize(width: 16, height: 16)
    private static var cache: [Provider: NSImage] = [:]

    static func image(for provider: Provider) -> NSImage? {
        if let cached = cache[provider] {
            return cached
        }
        guard let url = Bundle.main.url(forResource: provider.iconResourceName, withExtension: "svg"),
              let image = NSImage(contentsOf: url) else {
            return nil
        }
        image.size = size
        image.isTemplate = true
        cache[provider] = image
        return image
    }
}
