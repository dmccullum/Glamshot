import CoreGraphics
import Foundation

/// How to photograph the page itself, before any framing.
public struct CaptureOptions: Codable, Hashable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case light, dark

        public var title: String { self == .light ? "Light" : "Dark" }
    }

    /// The viewport in points.
    public var width: Int
    public var height: Int
    public var scale: Int
    /// The whole scrolling height instead of one screen.
    public var fullPage: Bool
    /// Seconds to wait after the page settles, for animations and late content.
    public var delay: Double
    public var appearance: Appearance
    public var userAgent: UserAgent
    /// CSS selectors hidden while photographing, one per line or comma-separated.
    public var hiddenSelectors: String

    public init(
        width: Int = SizePreset.macBookPro14.width,
        height: Int = SizePreset.macBookPro14.height,
        scale: Int = 2,
        fullPage: Bool = false,
        delay: Double = 0.5,
        appearance: Appearance = .light,
        userAgent: UserAgent = .mac,
        hiddenSelectors: String = ""
    ) {
        self.width = width
        self.height = height
        self.scale = scale
        self.fullPage = fullPage
        self.delay = delay
        self.appearance = appearance
        self.userAgent = userAgent
        self.hiddenSelectors = hiddenSelectors
    }

    public var viewport: CGSize { CGSize(width: width, height: height) }

    public mutating func apply(_ preset: SizePreset) {
        width = preset.width
        height = preset.height
        scale = preset.scale
        userAgent = preset.userAgent
    }

    /// Whether this viewport is the preset's, ignoring scale.
    public func matches(_ preset: SizePreset) -> Bool {
        width == preset.width && height == preset.height
    }

    /// The tallest full-page image, in pixels. Taller pages are cut here.
    public static let maximumPixelHeight = 32_768

    /// The hidden selectors as one stylesheet rule, or nil when there are none.
    public var hidingStylesheet: String? {
        let selectors = hiddenSelectors
            .split(whereSeparator: { $0 == "\n" || $0 == "," })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        guard !selectors.isEmpty else { return nil }
        return selectors.joined(separator: ", ") + " { visibility: hidden !important; }"
    }
}
