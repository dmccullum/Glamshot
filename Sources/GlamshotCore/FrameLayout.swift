import CoreGraphics

/// Where everything goes in a finished shot, in points with the origin at the top left.
///
/// For a device's screen (a Mac, display, iPad or iPhone size, or a custom one), the size is the
/// screen's: the window keeps it, chrome and page together, and a canvas's padding or a shadow's
/// room goes around it, so padding is even on every side. A full page works the same way, with the
/// page's length as its height. A social size is the finished image instead: the padding comes out
/// of it and the page gets what's left. On a desktop the size is the desktop's.
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
            let area = CGRect(x: 0, y: menuBar, width: output.width, height: max(output.height - menuBar, 1))
            let rect = desktopWindowRect(look.desktop, in: area, chrome: chrome)
            let page = pageRect(in: rect, chrome: chrome)
            return FrameLayout(
                canvasSize: output, windowRect: rect, pageRect: page,
                chromeHeight: chrome, menuBarHeight: menuBar, pageSize: page.size
            )
        }

        let inset = insets(for: look, output: output, chrome: chrome)

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
    /// The smallest window a desktop allows, in points.
    public static let minimumWindowSize = CGSize(width: 360, height: 240)

    /// Padding Auto Padding uses: 7% of the output's shorter side, between 24 and 160 points.
    public static func automaticPadding(for output: CGSize) -> CGFloat {
        min(max((min(output.width, output.height) * 0.07).rounded(), 24), 160)
    }

    /// Room around the window on every side: the canvas padding, or on no backdrop, space for the
    /// shadow so a transparent image doesn't cut it off.
    static func insets(for look: Look, output: CGSize, chrome: CGFloat) -> CGFloat {
        let wanted: CGFloat
        switch look.backdrop {
        case .none:
            wanted = look.shadow > 0 ? (ChromeMetrics.shadowMargin * min(look.shadow, 1)).rounded() : 0
        case .canvas:
            wanted = look.canvas.autoPadding ? automaticPadding(for: output) : max(look.canvas.padding, 0)
        case .desktop:
            wanted = 0
        }
        // Never so much that the page disappears.
        let limit = max(min((output.width - minimumPageSize.width) / 2, (output.height - chrome - minimumPageSize.height) / 2), 0)
        return min(wanted, limit).rounded()
    }

    static func desktopWindowRect(_ desktop: DesktopOptions, in area: CGRect, chrome: CGFloat) -> CGRect {
        let size = CGSize(
            width: min(max(area.width * desktop.widthFraction, minimumWindowSize.width), area.width).rounded(),
            height: min(max(area.height * desktop.heightFraction, max(minimumWindowSize.height, chrome + 1)), area.height).rounded()
        )
        var origin = CGPoint(
            x: area.minX + area.width * desktop.centerX - size.width / 2,
            y: area.minY + area.height * desktop.centerY - size.height / 2
        )
        origin.x = min(max(origin.x, area.minX), area.maxX - size.width).rounded()
        origin.y = min(max(origin.y, area.minY), area.maxY - size.height).rounded()
        return CGRect(origin: origin, size: size)
    }

    /// Snaps a moving window's center to the middle of `area` across, down or both, when it comes
    /// within `tolerance` points, as Final Cut and other editors snap to center guides.
    public static func snapToCenter(_ rect: CGRect, in area: CGRect, tolerance: CGFloat) -> (rect: CGRect, x: Bool, y: Bool) {
        var snapped = rect
        let x = abs(rect.midX - area.midX) <= tolerance
        let y = abs(rect.midY - area.midY) <= tolerance
        if x { snapped.origin.x = (area.midX - rect.width / 2).rounded() }
        if y { snapped.origin.y = (area.midY - rect.height / 2).rounded() }
        return (snapped, x, y)
    }

    /// The desktop's area below the menu bar, where the window lives.
    public static func desktopArea(output: CGSize) -> CGRect {
        CGRect(x: 0, y: ChromeMetrics.menuBarHeight, width: output.width, height: output.height - ChromeMetrics.menuBarHeight)
    }

    /// Writes a window rect, in points on a desktop of `output`, back as fractions of the area
    /// below the menu bar.
    public static func desktopOptions(_ desktop: DesktopOptions, with rect: CGRect, output: CGSize) -> DesktopOptions {
        let area = CGRect(x: 0, y: ChromeMetrics.menuBarHeight, width: output.width, height: output.height - ChromeMetrics.menuBarHeight)
        var options = desktop
        let width = min(max(rect.width, minimumWindowSize.width), area.width)
        let height = min(max(rect.height, minimumWindowSize.height), area.height)
        options.widthFraction = width / area.width
        options.heightFraction = height / area.height
        options.centerX = min(max((rect.midX - area.minX) / area.width, 0), 1)
        options.centerY = min(max((rect.midY - area.minY) / area.height, 0), 1)
        return options
    }

    private static func pageRect(in window: CGRect, chrome: CGFloat) -> CGRect {
        CGRect(x: window.minX, y: window.minY + chrome, width: window.width, height: window.height - chrome)
    }
}
