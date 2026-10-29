import CoreGraphics

/// Where everything goes in a finished shot, in points with the origin at the top left.
///
/// A screen-sized shot is output first: the window and backdrop take their room from the output,
/// and the page gets what's left. A full page is the other way round: the width is the page's own,
/// its height is the page's length, and any padding and shadow go around it.
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

    /// Lays out `look` in an image of `output` points. For a full page, pass its height in points
    /// as `pageHeight`; `output.width` is then the page's width, not the image's.
    public static func make(output: CGSize, look: Look, pageHeight: CGFloat? = nil) -> FrameLayout {
        let chrome = look.window == .safari ? ChromeMetrics.chromeHeight(for: look.safari) : 0

        if look.backdrop == .desktop {
            let menuBar = ChromeMetrics.menuBarHeight
            let area = CGRect(x: 0, y: menuBar, width: output.width, height: max(output.height - menuBar, 1))
            let rect = desktopWindowRect(look.desktop, in: area, chrome: chrome)
            return FrameLayout(
                canvasSize: output, windowRect: rect, pageRect: pageRect(in: rect, chrome: chrome),
                chromeHeight: chrome, menuBarHeight: menuBar
            )
        }

        let inset = insets(for: look, output: output, chrome: chrome)
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
        return FrameLayout(
            canvasSize: canvas, windowRect: window, pageRect: pageRect(in: window, chrome: chrome),
            chromeHeight: chrome, menuBarHeight: 0
        )
    }

    /// The room the page gets, in points: the web view's size. A full page is the output's own
    /// width, with the output's height as its screen for anything sized from the viewport.
    public static func pageSize(output: CGSize, look: Look, fullPage: Bool = false) -> CGSize {
        fullPage ? output : make(output: output, look: look).pageRect.size
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
