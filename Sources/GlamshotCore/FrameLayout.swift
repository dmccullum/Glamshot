import CoreGraphics

/// Where everything goes in a finished shot, in points with the origin at the top left.
public struct FrameLayout: Equatable, Sendable {
    /// The whole image.
    public var canvasSize: CGSize
    /// The window's outer edge, or the page's when there's no window. It can run past the canvas
    /// when a tall page bleeds off the bottom.
    public var windowRect: CGRect
    /// Where the page image goes, below the chrome.
    public var pageRect: CGRect
    public var chromeHeight: CGFloat
    /// The menu bar's height on a desktop, otherwise 0.
    public var menuBarHeight: CGFloat

    /// Lays out a page of `page` points in `look`. On a desktop the window's size comes from the
    /// look, and the page should have been photographed at `Self.desktopViewport(for:)`.
    public static func make(page: CGSize, look: Look) -> FrameLayout {
        let chrome = look.window == .safari ? ChromeMetrics.chromeHeight(showsTabBar: look.safari.showsTabBar) : 0
        let window = CGSize(width: page.width, height: page.height + chrome)

        switch look.backdrop {
        case .none:
            let margin = look.window == .safari && look.safari.showsShadow ? ChromeMetrics.shadowMargin : 0
            let rect = CGRect(origin: CGPoint(x: margin, y: margin), size: window)
            return FrameLayout(
                canvasSize: CGSize(width: window.width + margin * 2, height: window.height + margin * 2),
                windowRect: rect, pageRect: pageRect(in: rect, chrome: chrome),
                chromeHeight: chrome, menuBarHeight: 0
            )

        case .canvas:
            return canvasLayout(window: window, chrome: chrome, options: look.canvas)

        case .desktop:
            let display = look.desktop.display.size
            let menuBar = ChromeMetrics.menuBarHeight
            let area = CGRect(x: 0, y: menuBar, width: display.width, height: display.height - menuBar)
            let size = clampedWindowSize(look.desktop.windowSize, chrome: chrome, in: area.size)
            var origin = CGPoint(
                x: area.minX + area.width * look.desktop.centerX - size.width / 2,
                y: area.minY + area.height * look.desktop.centerY - size.height / 2
            )
            origin.x = min(max(origin.x, area.minX), area.maxX - size.width).rounded()
            origin.y = min(max(origin.y, area.minY), area.maxY - size.height).rounded()
            let rect = CGRect(origin: origin, size: size)
            return FrameLayout(
                canvasSize: display, windowRect: rect, pageRect: pageRect(in: rect, chrome: chrome),
                chromeHeight: chrome, menuBarHeight: menuBar
            )
        }
    }

    /// The viewport to photograph for a desktop look: its window minus the chrome.
    public static func desktopViewport(for look: Look) -> CGSize {
        let layout = make(page: .zero, look: look)
        return layout.pageRect.size
    }

    /// The smallest window a desktop allows, in points.
    public static let minimumWindowSize = CGSize(width: 360, height: 240)

    static func clampedWindowSize(_ size: CGSize, chrome: CGFloat, in area: CGSize) -> CGSize {
        CGSize(
            width: min(max(size.width, minimumWindowSize.width), area.width).rounded(),
            height: min(max(size.height, max(minimumWindowSize.height, chrome + 1)), area.height).rounded()
        )
    }

    /// Padding Auto Balance uses: 8% of the window's width, between 32 and 200 points.
    public static func balancedPadding(for window: CGSize) -> CGFloat {
        min(max((window.width * 0.08).rounded(), 32), 200)
    }

    private static func canvasLayout(window: CGSize, chrome: CGFloat, options: CanvasOptions) -> FrameLayout {
        let padding = options.autoBalance ? balancedPadding(for: window) : max(options.padding, 0)
        var alignment = options.autoBalance ? CanvasAlignment.center.unit : options.alignment.unit
        let base = CGSize(width: window.width + padding * 2, height: window.height + padding * 2)
        var canvas = base

        if let ratio = options.aspect.value {
            if base.width / base.height > ratio {
                canvas.height = (base.width / ratio).rounded()
            } else if options.autoBalance {
                // Too tall for the ratio: keep the width and let the page run off the bottom,
                // the way a long page is usually shown in a mockup.
                canvas.height = (base.width / ratio).rounded()
                alignment = CanvasAlignment.top.unit
            } else {
                canvas.width = (base.height * ratio).rounded()
            }
        }

        let free = CGSize(width: canvas.width - window.width - padding * 2, height: canvas.height - window.height - padding * 2)
        let origin = CGPoint(
            x: (padding + max(free.width, 0) * alignment.x).rounded(),
            y: (padding + max(free.height, 0) * alignment.y).rounded()
        )
        let rect = CGRect(origin: origin, size: window)
        return FrameLayout(
            canvasSize: canvas, windowRect: rect, pageRect: pageRect(in: rect, chrome: chrome),
            chromeHeight: chrome, menuBarHeight: 0
        )
    }

    private static func pageRect(in window: CGRect, chrome: CGFloat) -> CGRect {
        CGRect(x: window.minX, y: window.minY + chrome, width: window.width, height: window.height - chrome)
    }
}
