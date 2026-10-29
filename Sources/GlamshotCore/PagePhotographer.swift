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
/// banners carry into the photograph. Its frame is the page's room in points (its `pageZoom` sets
/// how wide the page lays out in that room), and nothing else may resize
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
        try await run(Self.waitForImagesScript, arguments: ["visibleOnly": true])
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
        try await run(Self.settleMotionScript)
        // A full page starts at the top; the person's scroll position comes back afterwards.
        try await run("scrollTo(0, 0);" + Self.nextFrameBody)
        try await run(Self.recordHeightsScript)
        let maximumHeight = CGFloat(CaptureOptions.maximumPixelHeight / options.scale)

        // Grow the view to the page so everything is in view at once (lazy images load and
        // scroll-reveals fire without scrolling, which would leave headers and parallax in their
        // scrolled state), then put back anything sized from the viewport height (a 100vh hero)
        // and measure again.
        // Page heights come back in CSS pixels; a zoomed page draws them smaller in the view.
        let zoom = webView.pageZoom
        var pageHeight = try await number("return document.scrollingElement.scrollHeight") * zoom
        webView.setFrameSize(CGSize(width: viewport.width, height: min(max(pageHeight, viewport.height), maximumHeight)))
        try await run(Self.nextFrameScript)
        pageHeight = try await number(Self.pinViewportHeightsScript) * zoom

        let wasCut = pageHeight > maximumHeight
        let height = min(max(pageHeight, viewport.height), maximumHeight).rounded()
        webView.setFrameSize(CGSize(width: viewport.width, height: height))
        try await run(Self.waitForImagesScript, arguments: ["visibleOnly": false])

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

    /// Content that fades or slides in when scrolled into view would be photographed mid-way, or
    /// not at all. Jump every transition and animation to its end, and load lazy images now.
    static let settleMotionScript = """
        const style = document.createElement('style');
        style.id = 'glamshot-settle';
        style.textContent = `*, *::before, *::after {
            transition-duration: 0s !important; transition-delay: 0s !important;
            animation-duration: 0s !important; animation-delay: 0s !important;
            scroll-behavior: auto !important;
        }`;
        document.documentElement.appendChild(style);
        for (const img of document.querySelectorAll('img[loading="lazy"]')) img.loading = 'eager';
        // Animations driven by scrolling (parallax, scroll reveals) would play out against the
        // stretched view's height. Stop them, so the page shows its resting layout.
        window.__glamshotTimelines = [];
        for (const el of document.querySelectorAll('*')) {
            const timeline = getComputedStyle(el).animationTimeline;
            if (timeline && timeline !== 'auto' && timeline !== 'none') {
                window.__glamshotTimelines.push([el, el.getAttribute('style')]);
                el.style.setProperty('animation', 'none', 'important');
            }
        }
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
                // offsetHeight includes padding and border, so pin the border box.
                el.style.setProperty('box-sizing', 'border-box', 'important');
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

    /// Waits for images to load and decode and for the network to go quiet, within limits, so slow
    /// and late images make it into the photograph. With `visibleOnly`, images outside the view are
    /// left alone (lazy ones there would never load). Takes `visibleOnly` as an argument.
    static let waitForImagesScript = """
        const inView = img => {
            if (!visibleOnly) return true;
            const r = img.getBoundingClientRect();
            return r.bottom > 0 && r.right > 0 && r.top < innerHeight && r.left < innerWidth && r.width > 0;
        };
        const deadline = (ms) => new Promise(r => setTimeout(r, ms));
        const images = () => [...document.images].filter(inView);

        // Count every resource as it finishes; the timing buffer itself stops at 250 entries.
        let finished = 0, lastChange = performance.now();
        const observer = new PerformanceObserver(list => { finished += list.getEntries().length; lastChange = performance.now(); });
        observer.observe({ type: 'resource', buffered: false });

        const pending = images().filter(i => !i.complete || (i.currentSrc && i.naturalWidth === 0))
            .map(i => new Promise(r => { i.addEventListener('load', r, { once: true }); i.addEventListener('error', r, { once: true }); }));
        await Promise.race([Promise.all(pending), deadline(5000)]);

        // Then until nothing new has finished for 500 ms (at most 4 s), for images scripts add late.
        const start = performance.now();
        lastChange = Math.max(lastChange, start);
        while (performance.now() - start < 4000 && performance.now() - lastChange < 500) await deadline(100);
        observer.disconnect();

        // Decoded images draw at once; an undecoded one can come out blank.
        await Promise.race([
            Promise.all(images().filter(i => i.complete && i.naturalWidth > 0).map(i => i.decode().catch(() => {}))),
            deadline(2000)
        ]);
        await Promise.race([
            new Promise(r => requestAnimationFrame(() => requestAnimationFrame(r))),
            deadline(150)
        ]);
        """

    static let restoreScript = """
        document.getElementById('glamshot-settle')?.remove();
        for (const [el, style] of window.__glamshotTimelines || []) {
            if (style === null) el.removeAttribute('style'); else el.setAttribute('style', style);
        }
        delete window.__glamshotTimelines;
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
