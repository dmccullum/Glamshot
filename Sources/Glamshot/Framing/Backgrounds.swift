import AppKit
import GlamshotCore
import Observation
import SwiftUI
import UndertoneKit

/// The bundled organic gradients: Undertone recipes, by name.
enum GradientLibrary {
    struct Entry: Identifiable {
        let name: String
        /// Undertone color stops: hex color and position, 0…1 across and down.
        let stops: [(hex: String, x: Double, y: Double)]
        /// Whether the top of the gradient is dark, for an automatic menu bar.
        let topIsDark: Bool
        var id: String { name }
    }

    static let entries: [Entry] = [
        Entry(name: "Tahoe", stops: [("D7E8FF", 0.15, 0.12), ("4B8CFF", 0.78, 0.22), ("1F5EE0", 0.28, 0.78), ("0B3BB5", 0.88, 0.9), ("9CC2FF", 0.55, 0.5)], topIsDark: false),
        Entry(name: "Dusk", stops: [("F3AC91", 0.18, 0.20), ("7655A3", 0.78, 0.24), ("F3CC91", 0.34, 0.82), ("3B526E", 0.92, 0.85)], topIsDark: false),
        Entry(name: "Tidal", stops: [("E8DFC7", 0.2, 0.15), ("67B8AC", 0.7, 0.35), ("164E63", 0.35, 0.85), ("2C8C99", 0.9, 0.8)], topIsDark: false),
        Entry(name: "Bloom", stops: [("FFD6E7", 0.15, 0.15), ("E86FB8", 0.75, 0.25), ("B98AF2", 0.3, 0.75), ("5E4AC9", 0.85, 0.88)], topIsDark: false),
        Entry(name: "Citrus", stops: [("FFF2B3", 0.2, 0.12), ("FFB347", 0.8, 0.3), ("FF7B54", 0.25, 0.8), ("D9415E", 0.85, 0.9)], topIsDark: false),
        Entry(name: "Moss", stops: [("DCEFC2", 0.2, 0.15), ("6CBF84", 0.75, 0.3), ("2F7D62", 0.3, 0.8), ("123A33", 0.88, 0.88)], topIsDark: false),
        Entry(name: "Midnight", stops: [("22365F", 0.2, 0.15), ("4A3A8C", 0.8, 0.25), ("070D1C", 0.3, 0.85), ("1D3A6E", 0.85, 0.8)], topIsDark: true),
        Entry(name: "Ember", stops: [("842D43", 0.2, 0.2), ("E57E55", 0.75, 0.35), ("F4D8AB", 0.35, 0.85), ("4A1230", 0.9, 0.9)], topIsDark: true)
    ]

    static func entry(named name: String) -> Entry {
        entries.first { $0.name == name } ?? entries[0]
    }

    /// The entry's Undertone recipe. A nonzero seed moves the colors and the grain, so Shuffle
    /// gives a new arrangement of the same palette.
    static func recipe(named name: String, seed: UInt32) -> GradientRecipe {
        var generator = SeededGenerator(seed: UInt64(seed))
        let stops = entry(named: name).stops.map { stop in
            func nudge(_ value: Double) -> Double {
                seed == 0 ? value : min(max(value + .random(in: -0.22...0.22, using: &generator), 0.02), 0.98)
            }
            return ColorStop(hex: stop.hex, x: nudge(stop.x), y: nudge(stop.y))
        }
        var recipe = GradientRecipe(stops: stops, mode: .organic)
        recipe.seed = UInt64(seed) &+ 42
        recipe.grain = 0.16
        return recipe
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEAD_BEEF : seed &* 0x9E37_79B9_7F4A_7C15 }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// Renders gradients with Undertone off the main thread and keeps the window-sized previews.
@Observable
final class GradientCache {
    static let shared = GradientCache()

    struct Key: Hashable { let name: String; let seed: UInt32; let width: Int; let height: Int }

    @ObservationIgnored private var images: [Key: CGImage] = [:]
    @ObservationIgnored private var pending: Set<Key> = []
    /// Bumped when a render lands, so views showing a placeholder draw again.
    private(set) var generation = 0

    /// The preview for a gradient at roughly this aspect, or nil while it renders.
    func preview(name: String, seed: UInt32, aspect: CGSize) -> CGImage? {
        _ = generation
        let longest = 1024.0
        let scale = longest / max(aspect.width, aspect.height, 1)
        let key = Key(name: name, seed: seed, width: max(Int(aspect.width * scale), 16), height: max(Int(aspect.height * scale), 16))
        if let image = images[key] { return image }
        guard !pending.contains(key) else { return nil }
        pending.insert(key)
        let recipe = GradientLibrary.recipe(named: name, seed: seed)
        Task.detached(priority: .userInitiated) {
            let image = try? RenderEngine.render(recipe, width: key.width, height: key.height)
            await MainActor.run {
                self.pending.remove(key)
                if let image { self.images[key] = image }
                if self.images.count > 48 { self.images.removeAll() }
                self.generation += 1
            }
        }
        return nil
    }

    /// Renders a gradient at full output size for a saved image. Undertone stops at 8192 pixels on a
    /// side; larger canvases are drawn from that and scaled up, which the grain hides.
    nonisolated static func render(name: String, seed: UInt32, pixelSize: CGSize) async throws -> CGImage {
        let recipe = await GradientLibrary.recipe(named: name, seed: seed)
        let limit = 8_192.0
        let fit = min(1, limit / max(pixelSize.width, pixelSize.height, 1))
        var width = max(Int(pixelSize.width * fit), 1)
        var height = max(Int(pixelSize.height * fit), 1)
        while width * height > 33_554_432 {
            width = width * 9 / 10
            height = height * 9 / 10
        }
        let (w, h) = (width, height)
        return try await Task.detached(priority: .userInitiated) {
            try RenderEngine.render(recipe, width: w, height: h)
        }.value
    }
}

extension EnvironmentValues {
    /// A background rendered at full size for saving; when nil, the window's preview is used.
    @Entry var renderedBackground: CGImage?
}

/// A canvas or desktop fill, drawn the same in the window and in the saved image.
struct BackgroundView: View {
    let fill: BackgroundFill
    @Environment(\.renderedBackground) private var rendered

    var body: some View {
        switch fill {
        case .gradient(let name, let seed):
            GeometryReader { proxy in
                if let image = rendered ?? GradientCache.shared.preview(name: name, seed: seed, aspect: proxy.size) {
                    Image(decorative: image, scale: 1)
                        .resizable()
                        .interpolation(.high)
                } else {
                    // Undertone takes a moment; show the palette's average meanwhile.
                    LinearGradient(colors: GradientLibrary.entry(named: name).stops.compactMap { Color(hex: $0.hex) },
                                   startPoint: .topLeading, endPoint: .bottomTrailing)
                }
            }
        case .color(let hex):
            Color(hex: hex) ?? .white
        case .image(let path):
            if let image = NSImage(contentsOfFile: path) {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.gray
            }
        }
    }
}

extension BackgroundFill {
    /// Whether menu bar text should be light over this fill's top edge.
    var topIsDark: Bool {
        switch self {
        case .gradient(let name, _): GradientLibrary.entry(named: name).topIsDark
        case .color(let hex): (NSColor(hex: hex)?.luminance ?? 1) < 0.5
        case .image: false
        }
    }

    var title: String {
        switch self {
        case .gradient(let name, _): name
        case .color: "Color"
        case .image(let path): URL(fileURLWithPath: path).lastPathComponent
        }
    }
}

extension Color {
    init?(hex: String) {
        guard let color = NSColor(hex: hex) else { return nil }
        self.init(nsColor: color)
    }
}

extension NSColor {
    convenience init?(hex: String) {
        var text = hex.trimmingCharacters(in: .whitespaces)
        if text.hasPrefix("#") { text.removeFirst() }
        guard text.count == 6, let value = UInt32(text, radix: 16) else { return nil }
        self.init(srgbRed: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255,
                  blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }

    var hexString: String {
        let color = usingColorSpace(.sRGB) ?? self
        return String(format: "#%02X%02X%02X", Int(color.redComponent * 255), Int(color.greenComponent * 255), Int(color.blueComponent * 255))
    }

    var luminance: CGFloat {
        let color = usingColorSpace(.sRGB) ?? self
        return 0.2126 * color.redComponent + 0.7152 * color.greenComponent + 0.0722 * color.blueComponent
    }
}
