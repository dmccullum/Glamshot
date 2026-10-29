import CoreGraphics
import Foundation

/// What goes around the page: a browser window, and what the window sits on.
public struct Look: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public var window: WindowStyle
    public var backdrop: Backdrop
    public var safari: SafariOptions
    public var canvas: CanvasOptions
    public var desktop: DesktopOptions
    public var background: BackgroundFill
    /// The window's shadow, 0 for none to 1 for a full macOS window shadow. On no backdrop, any
    /// shadow adds transparent room around the window so it isn't cut off.
    public var shadow: CGFloat

    public init(
        id: String = UUID().uuidString,
        name: String,
        window: WindowStyle = .safari,
        backdrop: Backdrop = .none,
        safari: SafariOptions = SafariOptions(),
        canvas: CanvasOptions = CanvasOptions(),
        desktop: DesktopOptions = DesktopOptions(),
        background: BackgroundFill = .gradient(name: "Dusk", seed: 0),
        shadow: CGFloat = 0.7
    ) {
        self.id = id
        self.name = name
        self.window = window
        self.backdrop = backdrop
        self.safari = safari
        self.canvas = canvas
        self.desktop = desktop
        self.background = background
        self.shadow = shadow
    }

    /// “Safari on Canvas”, “Bare Page”, for window subtitles.
    public var summary: String {
        let window = self.window == .safari ? "Safari" : "Page"
        switch backdrop {
        case .none: return self.window == .safari ? "Safari" : "Bare Page"
        case .canvas: return "\(window) on Canvas"
        case .desktop: return "\(window) on Desktop"
        }
    }

    public static let builtIns: [Look] = [
        Look(id: "bare", name: "Bare Page", window: .none, backdrop: .none, shadow: 0),
        Look(id: "safari", name: "Safari, Transparent", window: .safari, backdrop: .none),
        Look(id: "canvas-4x5", name: "Safari on Canvas 4:5", window: .safari, backdrop: .canvas,
             canvas: CanvasOptions(aspect: .r4x5, autoBalance: true)),
        Look(id: "canvas-16x9", name: "Safari on Canvas 16:9", window: .safari, backdrop: .canvas,
             canvas: CanvasOptions(aspect: .r16x9, autoBalance: true), background: .gradient(name: "Tidal", seed: 0)),
        Look(id: "desktop", name: "Desktop", window: .safari, backdrop: .desktop, background: .gradient(name: "Bloom", seed: 0))
    ]
}

public enum WindowStyle: String, Codable, CaseIterable, Sendable {
    case none, safari

    public var title: String { self == .none ? "None" : "Safari" }
}

public enum Backdrop: String, Codable, CaseIterable, Sendable {
    case none, canvas, desktop

    public var title: String {
        switch self {
        case .none: "None"
        case .canvas: "Canvas"
        case .desktop: "Desktop"
        }
    }
}

public struct SafariOptions: Codable, Hashable, Sendable {
    public enum Appearance: String, Codable, CaseIterable, Sendable {
        case light, dark, matchPage

        public var title: String {
            switch self {
            case .light: "Light"
            case .dark: "Dark"
            case .matchPage: "Match Page"
            }
        }
    }

    public enum Address: String, Codable, CaseIterable, Sendable {
        case domain, fullURL, hidden

        public var title: String {
            switch self {
            case .domain: "Domain"
            case .fullURL: "Full Address"
            case .hidden: "Hidden"
            }
        }
    }

    public var appearance: Appearance = .matchPage
    public var address: Address = .domain
    public var showsTabBar: Bool = false

    public init(appearance: Appearance = .matchPage, address: Address = .domain, showsTabBar: Bool = false) {
        self.appearance = appearance
        self.address = address
        self.showsTabBar = showsTabBar
    }
}

public enum AspectRatio: String, Codable, CaseIterable, Sendable {
    case auto, r16x9, r3x2, r4x3, r1x1, r4x5, r9x16

    public var title: String {
        switch self {
        case .auto: "Auto"
        case .r16x9: "16:9"
        case .r3x2: "3:2"
        case .r4x3: "4:3"
        case .r1x1: "1:1"
        case .r4x5: "4:5"
        case .r9x16: "9:16"
        }
    }

    /// Width divided by height, or nil for Auto.
    public var value: CGFloat? {
        switch self {
        case .auto: nil
        case .r16x9: 16.0 / 9
        case .r3x2: 3.0 / 2
        case .r4x3: 4.0 / 3
        case .r1x1: 1
        case .r4x5: 4.0 / 5
        case .r9x16: 9.0 / 16
        }
    }
}

/// Where the window sits when the canvas has room to spare: a 3 × 3 grid.
public enum CanvasAlignment: String, Codable, CaseIterable, Sendable {
    case topLeading, top, topTrailing, leading, center, trailing, bottomLeading, bottom, bottomTrailing

    /// 0, 0.5 or 1 across and down.
    public var unit: CGPoint {
        let index = Self.allCases.firstIndex(of: self)!
        return CGPoint(x: CGFloat(index % 3) / 2, y: CGFloat(index / 3) / 2)
    }
}

/// The page or window on a background, with room around it.
public struct CanvasOptions: Codable, Hashable, Sendable {
    /// Space around the window in points, before the aspect ratio adds more.
    public var padding: CGFloat = 96
    public var aspect: AspectRatio = .auto
    public var alignment: CanvasAlignment = .center
    /// Picks padding and alignment for the window's shape: a tall page bleeds off the bottom.
    public var autoBalance: Bool = true
    /// Corner radius for a page with no window, in points.
    public var cornerRadius: CGFloat = 14

    public init(padding: CGFloat = 96, aspect: AspectRatio = .auto, alignment: CanvasAlignment = .center,
                autoBalance: Bool = true, cornerRadius: CGFloat = 14) {
        self.padding = padding
        self.aspect = aspect
        self.alignment = alignment
        self.autoBalance = autoBalance
        self.cornerRadius = cornerRadius
    }
}

/// A Mac desktop with a menu bar and the window on it.
public struct DesktopOptions: Codable, Hashable, Sendable {
    /// A Mac `SizePreset` id; its points are the desktop's size.
    public var displayID: String = SizePreset.macBookPro14.id
    /// The window's outer size in points, including the toolbar.
    public var windowWidth: CGFloat = 1210
    public var windowHeight: CGFloat = 760
    /// The window's center as a fraction of the area below the menu bar.
    public var centerX: CGFloat = 0.5
    public var centerY: CGFloat = 0.5
    public var appName: String = "Safari"
    public var clock: String = "Tue Oct 29  9:41 AM"
    /// Menu bar text: dark on a light desktop, light on a dark one.
    public var menuBar: MenuBarAppearance = .automatic

    public init() {}

    public var windowSize: CGSize {
        get { CGSize(width: windowWidth, height: windowHeight) }
        set { windowWidth = newValue.width; windowHeight = newValue.height }
    }

    public var display: SizePreset {
        SizePreset.builtIns.first { $0.id == displayID } ?? .macBookPro14
    }
}

public enum MenuBarAppearance: String, Codable, CaseIterable, Sendable {
    /// Chosen from the background's brightness under the menu bar.
    case automatic, light, dark

    public var title: String {
        switch self {
        case .automatic: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }
}

/// What a canvas or desktop is filled with.
public enum BackgroundFill: Codable, Hashable, Sendable {
    /// One of the bundled Undertone recipes, by name, with a grain and shape seed.
    case gradient(name: String, seed: UInt32)
    /// An sRGB color as “#RRGGBB”.
    case color(hex: String)
    /// An image file.
    case image(path: String)
}
