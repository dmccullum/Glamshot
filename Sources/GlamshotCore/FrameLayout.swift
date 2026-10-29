import CoreGraphics

/// Where everything goes in a finished shot, in points with the origin at the top left.
///
/// For a device's screen (a Mac, display, iPad or iPhone size, or a custom one), the size is the
/// screen's: the window keeps it, chrome and page together, and a canvas's padding or a shadow's
/// room goes around it, so padding is even on every side. A full page works the same way, with the
/// page's length as its height. A social size is the finished image instead: the padding comes out
/// of it and the page gets what's left. On a desktop the size is the desktop's, and the window
/// fills it below the menu bar, inset by the padding on every side.
public struct FrameLayout: Equatable, Sendable {
    /// The whole image.
    public var canvasSize: CGSize
    /// The window's outer edge, or the page's when there's no window.
    public var windowRect: CGRect
    /// Where the page image goes, below the chrome.
    public var pageRect: CGRect
    public var chromeHeight: CGFloat
    /// The menu bar's height on a desktop, otherwise 0.
    public var menuBarHeight: CGFloat
    /// How much the window is drawn smaller than its real size: below 1 when a device screen is
    /// scaled into a canvas or shadow margin.
    public var windowScale: CGFloat = 1
    /// The page's real size in points, which the page lays out in; `pageRect` is that size times
    /// `windowScale`.
    public var pageSize: CGSize = .zero

    /// Lays out `look` in an image of `output` points. For a full page, pass its height in points
    /// as `pageHeight`; `output.width` is then the page's width, not the image's.
    public static func make(output: CGSize, look: Look, pageHeight: CGFloat? = nil) -> FrameLayout {
        let chrome = look.window == .safari ? ChromeMetrics.chromeHeight(for: look.safari) : 0

        if look.backdrop == .desktop {
            let menuBar = ChromeMetrics.menuBarHeight
            let area = desktopArea(output: output)
            let inset = insets(for: look, output: area.size, padding: padding(for: look, output: output), chrome: chrome)
            let rect = area.insetBy(dx: inset, dy: inset)
            let page = pageRect(in: rect, chrome: chrome)
            return FrameLayout(
                canvasSize: output, windowRect: rect, pageRect: page,
                chromeHeight: chrome, menuBarHeight: menuBar, pageSize: page.size
            )
        }

        let inset = insets(for: look, output: output, padding: padding(for: look, output: output), chrome: chrome)

        // A device screen keeps its real size and the frame grows around it.
        if pageHeight == nil, SizePreset.isScreen(output) {
            let window = CGRect(x: inset, y: inset, width: output.width, height: output.height)
            let page = pageRect(in: window, chrome: chrome)
            return FrameLayout(
                canvasSize: CGSize(width: output.width + inset * 2, height: output.height + inset * 2),
                windowRect: window, pageRect: page, chromeHeight: chrome, menuBarHeight: 0, pageSize: page.size
            )
        }

        var window = CGRect(
            x: inset, y: inset,
            width: max(output.width - inset * 2, minimumPageSize.width),
            height: max(output.height - inset * 2, chrome + minimumPageSize.height)
        )
        var canvas = output
        if let pageHeight {
            window.size = CGSize(width: output.width, height: chrome + max(pageHeight, 1))
            canvas = CGSize(width: window.width + inset * 2, height: window.height + inset * 2)
        }
        let page = pageRect(in: window, chrome: chrome)
        return FrameLayout(
            canvasSize: canvas, windowRect: window, pageRect: page,
            chromeHeight: chrome, menuBarHeight: 0, pageSize: page.size
        )
    }

    /// The room the page gets, in points: the web view's size. A full page is the output's own
    /// width, with the output's height as its screen for anything sized from the viewport.
    public static func pageSize(output: CGSize, look: Look, fullPage: Bool = false) -> CGSize {
        fullPage ? output : make(output: output, look: look).pageSize
    }

    /// The smallest page Glamshot lays out, in points.
    public static let minimumPageSize = CGSize(width: 200, height: 120)

    /// Padding Auto Padding uses: 7% of the output's shorter side, between 24 and 160 points.
    public static func automaticPadding(for output: CGSize) -> CGFloat {
        min(max((min(output.width, output.height) * 0.07).rounded(), 24), 160)
    }

    /// The padding a canvas or desktop asks for: the automatic amount for the whole output, or
    /// the custom one.
    static func padding(for look: Look, output: CGSize) -> CGFloat {
        look.canvas.autoPadding ? automaticPadding(for: output) : max(look.canvas.padding, 0)
    }

    /// Room around the window on every side of `output`: the padding on a canvas or desktop, or on
    /// no backdrop, space for the shadow so a transparent image doesn't cut it off.
    static func insets(for look: Look, output: CGSize, padding: CGFloat, chrome: CGFloat) -> CGFloat {
        let wanted = look.backdrop == .none
            ? (look.shadow > 0 ? (ChromeMetrics.shadowMargin * min(look.shadow, 1)).rounded() : 0)
            : padding
        // Never so much that the page disappears.
        let limit = max(min((output.width - minimumPageSize.width) / 2, (output.height - chrome - minimumPageSize.height) / 2), 0)
        return min(wanted, limit).rounded()
    }

    /// The desktop's area below the menu bar, where the window lives.
    public static func desktopArea(output: CGSize) -> CGRect {
        CGRect(x: 0, y: ChromeMetrics.menuBarHeight, width: output.width, height: max(output.height - ChromeMetrics.menuBarHeight, 1))
    }

    private static func pageRect(in window: CGRect, chrome: CGFloat) -> CGRect {
        CGRect(x: window.minX, y: window.minY + chrome, width: window.width, height: window.height - chrome)
    }
}
