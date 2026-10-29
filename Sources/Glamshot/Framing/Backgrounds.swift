import AppKit
import GlamshotCore
import SwiftUI

/// The bundled organic gradients, by name.
enum GradientLibrary {
    struct Entry: Identifiable {
        let name: String
        /// Nine colors, a 3 × 3 mesh read left to right, top to bottom.
        let colors: [Color]
        /// Whether the top of the gradient is dark, for an automatic menu bar.
        let topIsDark: Bool
        var id: String { name }
    }

    static let entries: [Entry] = [
        Entry(name: "Tahoe", colors: hex("#BFD9FF", "#6FA8FF", "#E8F1FF", "#2E6BEA", "#4B8CFF", "#9CC2FF", "#0B3BB5", "#1F5EE0", "#62A0FF"), topIsDark: false),
        Entry(name: "Dusk", colors: hex("#FFB59A", "#F28AA8", "#A48BE0", "#F4796B", "#C7609E", "#6E5BC7", "#3A2A6E", "#5B3E9C", "#2B2460"), topIsDark: false),
        Entry(name: "Lagoon", colors: hex("#B8F0E6", "#62D2C8", "#2FA7C2", "#5CC8B5", "#1E95A8", "#1B6E9C", "#0F4C6E", "#155D80", "#0A3550"), topIsDark: false),
        Entry(name: "Bloom", colors: hex("#FFD6E7", "#FFB0C9", "#F7C9FF", "#FF85A8", "#E86FB8", "#B98AF2", "#C94F8C", "#8E5BD6", "#5E4AC9"), topIsDark: false),
        Entry(name: "Citrus", colors: hex("#FFF2B3", "#FFD666", "#FFB347", "#FFC94D", "#FF9A3D", "#FF7B54", "#FF8A3D", "#F25C54", "#D9415E"), topIsDark: false),
        Entry(name: "Moss", colors: hex("#DCEFC2", "#A9D88B", "#6CBF84", "#8CC77A", "#4FA36B", "#2F7D62", "#2E6B4F", "#1F5444", "#123A33"), topIsDark: false),
        Entry(name: "Midnight", colors: hex("#1B2A4A", "#22365F", "#3A2F6B", "#0F1B33", "#1D3A6E", "#4A3A8C", "#070D1C", "#13244A", "#2A2363"), topIsDark: true),
        Entry(name: "Ember", colors: hex("#3B0F1F", "#6E1E2F", "#2B0F2E", "#A3302F", "#D9542B", "#6B1F3F", "#F28A2E", "#C73E2A", "#4A1230"), topIsDark: true)
    ]

    static func entry(named name: String) -> Entry {
        entries.first { $0.name == name } ?? entries[0]
    }

    private static func hex(_ values: String...) -> [Color] {
        values.map { Color(hex: $0) ?? .gray }
    }

    /// The mesh's inner points, nudged by the seed so Shuffle gives a new shape.
    static func points(seed: UInt32) -> [SIMD2<Float>] {
        var generator = SeededGenerator(seed: UInt64(seed) &+ 0x9E37_79B9)
        func wobble(_ base: Float, _ amount: Float) -> Float {
            seed == 0 ? base : base + Float.random(in: -amount...amount, using: &generator)
        }
        return [
            [0, 0], [wobble(0.5, 0.3), 0], [1, 0],
            [0, wobble(0.5, 0.3)], [wobble(0.5, 0.25), wobble(0.5, 0.25)], [1, wobble(0.5, 0.3)],
            [0, 1], [wobble(0.5, 0.3), 1], [1, 1]
        ]
    }
}

struct SeededGenerator: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed == 0 ? 0xDEAD_BEEF : seed }
    mutating func next() -> UInt64 {
        state ^= state << 13
        state ^= state >> 7
        state ^= state << 17
        return state
    }
}

/// A canvas or desktop fill, drawn the same in the window and in the saved image.
struct BackgroundView: View {
    let fill: BackgroundFill

    var body: some View {
        switch fill {
        case .gradient(let name, let seed):
            let entry = GradientLibrary.entry(named: name)
            MeshGradient(width: 3, height: 3, points: GradientLibrary.points(seed: seed), colors: entry.colors,
                         smoothsColors: true)
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
