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

    /// This look as drawn for an output: its Safari device worked out from the size; a desktop
    /// only for Mac sizes; and for a full page no window and no desktop, since no browser shows a
    /// whole page at once.
    public func resolved(for output: CGSize, fullPage: Bool = false) -> Look {
        var look = self
        look.safari.device = safari.resolvedDevice(for: output)
        if look.safari.device != .mac, look.backdrop == .desktop { look.backdrop = .canvas }
        if fullPage {
            look.window = .none
            if look.backdrop == .desktop { look.backdrop = .canvas }
        }
        return look
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

    /// What a new window starts with: a Safari window, no backdrop.
    public static let standard = Look(name: "Safari", window: .safari, backdrop: .none)
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
    public enum Address: String, Codable, CaseIterable, Sendable {
        /// `custom` shows the window's own text, such as a production domain over a staging page.
        case domain, fullURL, custom, hidden

        public var title: String {
            switch self {
            case .domain: "Domain"
            case .fullURL: "Full"
            case .custom: "Custom"
            case .hidden: "Hidden"
            }
        }
    }

    /// Which Safari is drawn. It always follows the output size (see `resolvedDevice(for:)`): iPhone
    /// sizes get Safari on iPhone, iPad sizes Safari on iPad, everything else Safari on the Mac.
    public enum Device: String, Codable, CaseIterable, Sendable {
        case automatic, mac, iPad, iPhone

        public var title: String {
            switch self {
            case .automatic: "Automatic"
            case .mac: "Mac"
            case .iPad: "iPad"
            case .iPhone: "iPhone"
            }
        }
    }

    /// Safari on iPhone's address bar: full, or shrunk to the domain as it is after scrolling.
    public enum PhoneBar: String, Codable, CaseIterable, Sendable {
        case full, minimized

        public var title: String { self == .full ? "Full" : "Minimized" }
    }

    public var device: Device = .automatic
    public var phoneBar: PhoneBar = .full
    public var address: Address = .domain
    public var showsTabBar: Bool = false

    public init(device: Device = .automatic, address: Address = .domain, showsTabBar: Bool = false) {
        self.device = device
        self.address = address
        self.showsTabBar = showsTabBar
    }

    /// The device to draw for an output size: iPhone for phone sizes and phone-shaped custom sizes,
    /// iPad for the iPad sizes, otherwise the Mac.
    public func resolvedDevice(for output: CGSize) -> Device {
        let match = SizePreset.builtIns.first { CGFloat($0.width) == output.width && CGFloat($0.height) == output.height }
        switch match?.group {
        case .phone: return .iPhone
        case .tablet: return .iPad
        case .some(.custom), nil: return output.width <= 500 && output.height > output.width ? .iPhone : .mac
        case .some: return .mac
        }
    }
}

/// The page or window on a background, with room around it.
public struct CanvasOptions: Codable, Hashable, Sendable {
    /// Picks the padding from the output size.
    public var autoPadding: Bool = true
    /// Space around the window in points when `autoPadding` is off.
    public var padding: CGFloat = 96
    /// Corner radius for a page with no window, in points.
    public var cornerRadius: CGFloat = 14

    public init(autoPadding: Bool = true, padding: CGFloat = 96, cornerRadius: CGFloat = 14) {
        self.autoPadding = autoPadding
        self.padding = padding
        self.cornerRadius = cornerRadius
    }
}

/// A Mac desktop with a menu bar and the window on it. The output size is the desktop's size; the
/// window is kept as a share of it, so a Look fits any output.
public struct DesktopOptions: Codable, Hashable, Sendable {
    /// The window's outer size as a fraction of the area below the menu bar.
    public var widthFraction: CGFloat = 0.8
    public var heightFraction: CGFloat = 0.8
    /// The window's center as a fraction of the area below the menu bar.
    public var centerX: CGFloat = 0.5
    public var centerY: CGFloat = 0.5
    public var appName: String = "Safari"
    public var clock: String = "Tue Oct 29  9:41 AM"
    /// Menu bar text: dark on a light desktop, light on a dark one.
    public var menuBar: MenuBarAppearance = .automatic

    public init() {}
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
