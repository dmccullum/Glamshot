import AppKit
import WebKit

public enum CaptureError: LocalizedError, Equatable {
    case noPage
    case snapshotFailed
    case imageTooLarge

    public var errorDescription: String? {
        switch self {
        case .noPage: "There’s no page to photograph yet."
        case .snapshotFailed: "WebKit didn’t return an image of the page."
        case .imageTooLarge: "The image is too large to create."
        }
    }

    public var recoverySuggestion: String? {
        switch self {
        case .noPage: "Type a web address and wait for the page to load, then try again."
        case .snapshotFailed: "Reload the page and try again."
        case .imageTooLarge: "Choose a smaller size or a lower scale."
        }
    }
}

/// A photograph of a page, before framing.
public struct PageCapture: @unchecked Sendable {
    public let image: CGImage
    /// The image's size in points; the pixel size divided by `scale`.
    public let pointSize: CGSize
    public let scale: Int
    /// True when a full page was taller than `CaptureOptions.maximumPixelHeight` and was cut there.
    public let wasCut: Bool

    public init(image: CGImage, pointSize: CGSize, scale: Int, wasCut: Bool = false) {
        self.image = image
        self.pointSize = pointSize
        self.scale = scale
        self.wasCut = wasCut
    }
}

/// Photographs the page in a web view: one screen, or the whole scrolling length.
///
/// The web view is the one the person is looking at and clicking in, so sign-ins and dismissed
/// banners carry into the photograph. Its frame must be the viewport, and nothing else may resize
/// it while a full-page capture runs, because the capture grows it to the page's height.
@MainActor
public final class PagePhotographer {
    public let webView: WKWebView

    /// The tallest tile WebKit is asked to draw at once, in points.
    static let tileHeight: CGFloat = 4_096

    public init(webView: WKWebView) {
        self.webView = webView
    }

    /// The capture under way. Captures run one at a time, since a full-page capture resizes the view.
    private var current: Task<PageCapture, any Error>?

    public func capture(_ options: CaptureOptions) async throws -> PageCapture {
        guard webView.url != nil else { throw CaptureError.noPage }
        let previous = current
        let task = Task {
            _ = try? await previous?.value
            try await settle(delay: options.delay)
            return options.fullPage ? try await captureFullPage(options) : try await captureViewport(options)
        }
        current = task
        return try await task.value
    }

    // MARK: Viewport

    private func captureViewport(_ options: CaptureOptions) async throws -> PageCapture {
        let rect = CGRect(origin: .zero, size: webView.bounds.size)
        let image = try await snapshot(rect, scale: options.scale)
        return PageCapture(image: image, pointSize: rect.size, scale: options.scale)
    }

    // MARK: Full page

    private func captureFullPage(_ options: CaptureOptions) async throws -> PageCapture {
        let viewport = webView.frame.size
        let scrollY = try await number("return window.scrollY")
        let result: Result<PageCapture, any Error>
        do {
            result = .success(try await photographWholePage(options, viewport: viewport))
        } catch {
            result = .failure(error)
        }
        webView.setFrameSize(viewport)
        _ = try? await run(Self.restoreScript, arguments: ["y": Double(scrollY)])
        return try result.get()
    }

    private func photographWholePage(_ options: CaptureOptions, viewport: CGSize) async throws -> PageCapture {
        try await run(Self.scrollThroughScript)
        try await run(Self.recordHeightsScript)
        let maximumHeight = CGFloat(CaptureOptions.maximumPixelHeight / options.scale)

        // Grow the view to the page so everything lays out and lazy images load, then put back
        // anything sized from the viewport height (a 100vh hero) and measure again.
        var pageHeight = try await number("return document.scrollingElement.scrollHeight")
        webView.setFrameSize(CGSize(width: viewport.width, height: min(max(pageHeight, viewport.height), maximumHeight)))
        try await run(Self.nextFrameScript)
        pageHeight = try await number(Self.pinViewportHeightsScript)

        let wasCut = pageHeight > maximumHeight
        let height = min(max(pageHeight, viewport.height), maximumHeight).rounded()
        webView.setFrameSize(CGSize(width: viewport.width, height: height))
        try await run(Self.waitForImagesScript)

        var tiles: [(image: CGImage, y: Int)] = []
        var y: CGFloat = 0
        while y < height {
            let rect = CGRect(x: 0, y: y, width: viewport.width, height: min(Self.tileHeight, height - y))
            tiles.append((try await snapshot(rect, scale: options.scale), Int(y) * options.scale))
            y += rect.height
        }
        let image = try Stitcher.stitch(
            tiles, width: Int(viewport.width) * options.scale, height: Int(height) * options.scale
        )
        return PageCapture(
            image: image, pointSize: CGSize(width: viewport.width, height: height),
            scale: options.scale, wasCut: wasCut
        )
    }

    // MARK: Snapshots

    /// Draws `rect` (in the view's points) at `scale` pixels per point. WebKit renders the content
    /// again at that size rather than enlarging what's on screen.
    func snapshot(_ rect: CGRect, scale: Int) async throws -> CGImage {
        let configuration = WKSnapshotConfiguration()
        configuration.rect = rect
        configuration.afterScreenUpdates = false
        let backingScale = webView.window?.backingScaleFactor ?? 2
        configuration.snapshotWidth = NSNumber(value: Double(rect.width) * Double(scale) / Double(backingScale))

        let image = try await webView.takeSnapshot(configuration: configuration)
        let pixelWidth = Int((rect.width * CGFloat(scale)).rounded())
        let pixelHeight = Int((rect.height * CGFloat(scale)).rounded())
        var proposed = CGRect(origin: .zero, size: image.size)
        guard let cgImage = image.cgImage(forProposedRect: &proposed, context: nil, hints: nil) else {
            throw CaptureError.snapshotFailed
        }
        if cgImage.width == pixelWidth, cgImage.height == pixelHeight { return cgImage }
        return try Stitcher.stitch([(cgImage, 0)], width: pixelWidth, height: pixelHeight)
    }

    // MARK: Page scripts

    /// Waits for web fonts and two frames, then the person's delay.
    func settle(delay: Double) async throws {
        try await run("await Promise.race([document.fonts.ready, new Promise(r => setTimeout(r, 2000))]);" + Self.nextFrameBody)
        if delay > 0 { try await Task.sleep(for: .seconds(delay)) }
    }

    @discardableResult
    func run(_ script: String, arguments: [String: Any] = [:]) async throws -> Any? {
        try await webView.callAsyncJavaScript(script, arguments: arguments, in: nil, contentWorld: .defaultClient)
    }

    func number(_ script: String) async throws -> CGFloat {
        CGFloat((try await run(script) as? NSNumber)?.doubleValue ?? 0)
    }

    /// Two animation frames, or 150 ms when the window is hidden and WebKit stops drawing frames.
    private static let nextFrameBody = """
        await Promise.race([
            new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))),
            new Promise(r => setTimeout(r, 150))
        ]);
        """
    static let nextFrameScript = nextFrameBody

    /// Scrolls down a screen at a time so scroll-triggered content and lazy images appear.
    static let scrollThroughScript = """
        const step = Math.max(200, innerHeight * 0.9);
        const end = document.scrollingElement.scrollHeight;
        for (let y = 0; y < end && y < 40000; y += step) {
            scrollTo(0, y);
            await new Promise(r => setTimeout(r, 80));
        }
        scrollTo(0, 0);
        await new Promise(r => setTimeout(r, 150));
        """

    static let recordHeightsScript = """
        const heights = new Map();
        for (const el of document.querySelectorAll('body, body *')) heights.set(el, el.offsetHeight);
        window.__glamshot = { heights, pinned: [] };
        """

    /// After the view grows, anything taller than before was sized from the viewport height. Pin
    /// it to its old height, then report the page's real height.
    static let pinViewportHeightsScript = """
        const state = window.__glamshot;
        for (const [el, old] of state.heights) {
            if (el.isConnected && el.offsetHeight > old + 1) {
                state.pinned.push([el, el.getAttribute('style')]);
                el.style.setProperty('height', old + 'px', 'important');
                el.style.setProperty('min-height', old + 'px', 'important');
                el.style.setProperty('max-height', old + 'px', 'important');
            }
        }
        await Promise.race([
            new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))),
            new Promise(r => setTimeout(r, 150))
        ]);
        return document.scrollingElement.scrollHeight;
        """

    static let waitForImagesScript = """
        const pending = [...document.images].filter(i => !i.complete)
            .map(i => new Promise(r => { i.addEventListener('load', r); i.addEventListener('error', r); }));
        await Promise.race([Promise.all(pending), new Promise(r => setTimeout(r, 3000))]);
        await Promise.race([
            new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))),
            new Promise(r => setTimeout(r, 150))
        ]);
        """

    static let restoreScript = """
        const state = window.__glamshot;
        if (state) {
            for (const [el, style] of state.pinned) {
                if (style === null) el.removeAttribute('style'); else el.setAttribute('style', style);
            }
            delete window.__glamshot;
        }
        scrollTo(0, y);
        """
}
