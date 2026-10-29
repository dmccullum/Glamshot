import AppKit
import DMKit
import GlamshotCore
import Observation
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// One window's shoot: the live page, how to photograph it, and how to frame it.
@Observable
final class ShootModel {
    // MARK: Page

    let webView: WKWebView
    @ObservationIgnored let photographer: PagePhotographer
    @ObservationIgnored private var observations: [NSKeyValueObservation] = []
    @ObservationIgnored private let navigation = NavigationDelegate()

    var addressText = ""
    private(set) var url: URL?
    private(set) var title = ""
    private(set) var isLoading = false
    private(set) var canGoBack = false
    private(set) var canGoForward = false
    /// The page's own background is dark, for Safari's Match Page appearance.
    private(set) var pageIsDark = false

    // MARK: Settings

    var capture: CaptureOptions { didSet { captureDidChange(from: oldValue) } }
    var look: Look { didSet { lookDidChange(from: oldValue) } }
    /// Sizes checked for Export Sizes….
    var exportSizeIDs: Set<String> = [SizePreset.macBookPro14.id]

    // MARK: Output

    var shots: [Shot] = []
    var status: StatusMessage?
    var alert: AlertContent?
    /// Work under way (saving, exporting), shown in the toolbar.
    var activity: Activity?
    /// A rendered still for full-page mode.
    private(set) var fullPagePreview: PageCapture?
    var zoom: CanvasZoom = .fit

    @ObservationIgnored weak var window: NSWindow?
    @ObservationIgnored var undoManager: UndoManager?
    @ObservationIgnored private var exportTask: Task<Void, Never>?

    init() {
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.hidingScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient
        ))
        webView = WKWebView(frame: CGRect(origin: .zero, size: CaptureOptions().viewport), configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = false
        webView.isInspectable = true
        photographer = PagePhotographer(webView: webView)

        let defaults = Defaults.shared
        capture = defaults.capture
        look = defaults.look
        webView.customUserAgent = capture.userAgent.string
        webView.appearance = NSAppearance(named: capture.appearance == .dark ? .darkAqua : .aqua)
        webView.navigationDelegate = navigation
        navigation.model = self
        observe()
        applyViewport()
    }

    private func observe() {
        observations = [
            webView.observe(\.url, options: [.initial, .new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.pageMoved(to: view.url) }
            },
            webView.observe(\.title, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.title = view.title ?? "" }
            },
            webView.observe(\.isLoading, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.isLoading = view.isLoading }
            },
            webView.observe(\.canGoBack, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoBack = view.canGoBack }
            },
            webView.observe(\.canGoForward, options: [.new]) { [weak self] view, _ in
                MainActor.assumeIsolated { self?.canGoForward = view.canGoForward }
            }
        ]
    }

    private func pageMoved(to url: URL?) {
        self.url = url
        if let url { addressText = url.absoluteString }
        fullPagePreview = nil
    }

    // MARK: Navigation

    var hasPage: Bool { url != nil }

    /// Loads what was typed: a URL, a bare domain, or a file path.
    func load(_ text: String) {
        guard let url = Self.url(from: text) else { return }
        load(url)
    }

    func load(_ url: URL) {
        addressText = url.absoluteString
        if url.isFileURL {
            webView.loadFileURL(url, allowingReadAccessTo: url.deletingLastPathComponent())
        } else {
            webView.load(URLRequest(url: url))
        }
        RecentPages.shared.add(url)
    }

    func reload() { webView.reload() }
    func stop() { webView.stopLoading() }
    func goBack() { webView.goBack() }
    func goForward() { webView.goForward() }

    static func url(from text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("~") {
            return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath)
        }
        if let url = URL(string: trimmed), let scheme = url.scheme, ["http", "https", "file"].contains(scheme.lowercased()) {
            return url
        }
        if !trimmed.contains(" "), trimmed.contains(".") || trimmed.hasPrefix("localhost") {
            return URL(string: (trimmed.hasPrefix("localhost") ? "http://" : "https://") + trimmed)
        }
        var components = URLComponents(string: "https://duckduckgo.com/")!
        components.queryItems = [URLQueryItem(name: "q", value: trimmed)]
        return components.url
    }

    fileprivate func pageFinishedLoading() {
        applyHiddenSelectors()
        Task { await readPageBackground() }
        if capture.fullPage { refreshFullPagePreview() }
    }

    fileprivate func pageFailed(_ error: any Error) {
        let error = error as NSError
        guard error.code != NSURLErrorCancelled else { return }
        alert = AlertContent(title: "Couldn’t Load Page", message: error.localizedDescription)
    }

    private func readPageBackground() async {
        let script = """
            const c = getComputedStyle(document.body).backgroundColor.match(/[\\d.]+/g) || [255,255,255,0];
            const h = getComputedStyle(document.documentElement).backgroundColor.match(/[\\d.]+/g) || [255,255,255,0];
            const pick = (c[3] === undefined || +c[3] > 0) ? c : h;
            return (0.2126 * pick[0] + 0.7152 * pick[1] + 0.0722 * pick[2]) / 255;
            """
        let luminance = (try? await webView.callAsyncJavaScript(script, contentWorld: .defaultClient) as? NSNumber)?.doubleValue
        pageIsDark = (luminance ?? 1) < 0.4
    }

    // MARK: Capture settings

    /// The preset matching the viewport, if any.
    var currentPreset: SizePreset? {
        Defaults.shared.allPresets.first { capture.matches($0) }
    }

    var sizeName: String {
        currentPreset?.name ?? "\(capture.width) × \(capture.height)"
    }

    func choose(_ preset: SizePreset) {
        setCapture(as: "Choose \(preset.name)") { $0.apply(preset) }
    }

    /// Changes the capture options as one named undo step.
    func setCapture(as name: String, _ change: (inout CaptureOptions) -> Void) {
        var new = capture
        change(&new)
        guard new != capture else { return }
        registerUndo(name)
        capture = new
    }

    func setLook(as name: String, _ change: (inout Look) -> Void) {
        var new = look
        change(&new)
        guard new != look else { return }
        registerUndo(name)
        look = new
    }

    /// Records the state before a change (the current state unless given) so undo puts it back.
    private func registerUndo(_ name: String, from snapshot: Snapshot? = nil) {
        let snapshot = snapshot ?? Snapshot(capture: capture, look: look)
        undoManager?.registerUndo(withTarget: self) { model in
            model.registerUndo(name)
            model.look = snapshot.look
            model.capture = snapshot.capture
        }
        undoManager?.setActionName(name)
    }

    struct Snapshot { var capture: CaptureOptions; var look: Look }

    // MARK: Continuous gestures

    @ObservationIgnored private var gestureStart: Snapshot?

    /// Starts a drag that changes settings many times; `endGesture` makes it one undo step.
    func beginGesture() {
        if gestureStart == nil { gestureStart = Snapshot(capture: capture, look: look) }
    }

    func endGesture(as name: String) {
        guard let start = gestureStart else { return }
        gestureStart = nil
        if start.look != look || start.capture != capture { registerUndo(name, from: start) }
    }

    // MARK: Address field

    /// Bumped to move focus to the address field.
    var addressFocusRequest = 0

    func focusAddress() { addressFocusRequest += 1 }

    private func captureDidChange(from old: CaptureOptions) {
        if capture.userAgent != old.userAgent {
            webView.customUserAgent = capture.userAgent.string
            if hasPage { webView.reload() }
        }
        if capture.appearance != old.appearance {
            webView.appearance = NSAppearance(named: capture.appearance == .dark ? .darkAqua : .aqua)
        }
        if capture.hiddenSelectors != old.hiddenSelectors { applyHiddenSelectors() }
        if capture.viewport != old.viewport { applyViewport() }
        if capture.fullPage != old.fullPage || capture.viewport != old.viewport || capture.scale != old.scale {
            fullPagePreview = nil
            if capture.fullPage { refreshFullPagePreview() }
        }
        Defaults.shared.capture = capture
    }

    private func lookDidChange(from old: Look) {
        if look.backdrop == .desktop, look.desktop != old.desktop || old.backdrop != .desktop
            || look.window != old.window || look.safari.showsTabBar != old.safari.showsTabBar {
            // On a desktop, the window's size is the viewport.
            let viewport = FrameLayout.desktopViewport(for: look)
            if viewport != capture.viewport {
                capture.width = Int(viewport.width)
                capture.height = Int(viewport.height)
            }
        }
        if look.backdrop == .desktop, capture.fullPage { capture.fullPage = false }
        Defaults.shared.look = look
    }

    /// Sizes the web view to the viewport. The host view scales it to fit the window.
    func applyViewport() {
        webView.setFrameSize(capture.viewport)
    }

    private func applyHiddenSelectors() {
        let css = capture.hidingStylesheet ?? ""
        webView.evaluateJavaScript(
            "window.__glamshotHide && window.__glamshotHide(\(Self.jsonString(css)))",
            in: nil, in: .defaultClient
        ) { _ in }
    }

    private static func jsonString(_ string: String) -> String {
        let data = (try? JSONSerialization.data(withJSONObject: [string])) ?? Data("[\"\"]".utf8)
        return String(decoding: data, as: UTF8.self) + "[0]"
    }

    static let hidingScriptSource = """
        window.__glamshotHide = function (css) {
            let style = document.getElementById('glamshot-hide');
            if (!style) {
                style = document.createElement('style');
                style.id = 'glamshot-hide';
                document.documentElement.appendChild(style);
            }
            style.textContent = css;
        };
        """

    // MARK: Desktop window

    func setDesktopWindow(size: CGSize? = nil, center: CGPoint? = nil, as name: String) {
        setLook(as: name) { look in
            if let size { look.desktop.windowSize = size }
            if let center {
                look.desktop.centerX = center.x
                look.desktop.centerY = center.y
            }
        }
    }

    func centerDesktopWindow() {
        setDesktopWindow(center: CGPoint(x: 0.5, y: 0.5), as: "Center Window")
    }

    func fillDesktop() {
        let display = look.desktop.display.size
        let size = CGSize(width: display.width - 48, height: display.height - ChromeMetrics.menuBarHeight - 48)
        setDesktopWindow(size: size, center: CGPoint(x: 0.5, y: 0.5), as: "Fill Desktop")
    }

    // MARK: Full-page preview

    func refreshFullPagePreview() {
        guard hasPage, capture.fullPage, !isLoading else { return }
        Task {
            var options = capture
            options.scale = 1
            options.delay = 0
            fullPagePreview = try? await photographer.capture(options)
        }
    }

    // MARK: Rendering

    /// Photographs the page and frames it at full resolution.
    func render(look: Look? = nil, capture: CaptureOptions? = nil) async throws -> RenderedShot {
        let look = look ?? self.look
        var options = capture ?? self.capture
        if look.backdrop == .desktop {
            let viewport = FrameLayout.desktopViewport(for: look)
            options.width = Int(viewport.width)
            options.height = Int(viewport.height)
            options.fullPage = false
        }
        let original = webView.frame.size
        if original != options.viewport { webView.setFrameSize(options.viewport) }
        defer { if original != options.viewport { webView.setFrameSize(original) } }
        let page = try await photographer.capture(options)
        let image = try await ShotRenderer.render(page: page, look: look, context: frameContext)
        return RenderedShot(image: image, scale: options.scale, wasCut: page.wasCut)
    }

    var frameContext: FrameContext {
        FrameContext(url: url, title: title, pageIsDark: pageIsDark)
    }

    func fileName(for look: Look? = nil, sizeName: String? = nil, capture: CaptureOptions? = nil) -> String {
        let options = capture ?? self.capture
        return FileNaming.name(Defaults.shared.fileNameTemplate, FileNaming.Context(
            url: url, title: title, sizeName: sizeName ?? self.sizeName,
            width: options.width, height: options.height, lookName: (look ?? self.look).name
        ))
    }

    // MARK: Save, copy, export

    func saveImage() async {
        guard hasPage else { return }
        let format = Defaults.shared.format
        let panel = NSSavePanel()
        panel.allowedContentTypes = [format.contentType]
        panel.nameFieldStringValue = fileName() + "." + format.fileExtension
        panel.canCreateDirectories = true
        if let folder = Defaults.shared.saveFolder { panel.directoryURL = folder }
        guard await panel.present(in: window) == .OK, let destination = panel.url else { return }
        Defaults.shared.saveFolder = destination.deletingLastPathComponent()
        await perform("Saving Image", failure: "Couldn’t Save Image") {
            let shot = try await self.render()
            try shot.write(to: destination, format: format)
            self.addShot(shot, file: destination)
            self.status = StatusMessage(
                "Saved “\(destination.lastPathComponent)”",
                leading: .thumbnail(NSImage(cgImage: shot.image, size: .zero)),
                action: .init("Show in Finder", help: "⇧⌘R") { NSWorkspace.shared.activateFileViewerSelecting([destination]) }
            )
            if shot.wasCut { self.status = StatusMessage("The page was cut at \(CaptureOptions.maximumPixelHeight) pixels tall") }
        }
    }

    func copyImage() async {
        guard hasPage else { return }
        await perform("Copying Image", failure: "Couldn’t Copy Image") {
            let shot = try await self.render()
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            pasteboard.writeObjects([NSImage(cgImage: shot.image, size: shot.pointSize)])
            if let png = shot.data(format: .png) { pasteboard.setData(png, forType: .png) }
            self.addShot(shot, file: nil)
            self.status = StatusMessage("Copied Image", leading: .thumbnail(NSImage(cgImage: shot.image, size: .zero)))
        }
    }

    /// Renders every checked size into a folder the person picks.
    func exportSizes() async {
        guard hasPage else { return }
        let presets = Defaults.shared.allPresets.filter { exportSizeIDs.contains($0.id) }
        guard !presets.isEmpty else { return }
        let panel = NSOpenPanel()
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "Export"
        panel.message = "Choose a folder for \(presets.count == 1 ? "1 image" : "\(presets.count) images")."
        if let folder = Defaults.shared.saveFolder { panel.directoryURL = folder }
        guard await panel.present(in: window) == .OK, let folder = panel.url else { return }
        Defaults.shared.saveFolder = folder

        let format = Defaults.shared.format
        let task = Task {
            var written: [URL] = []
            for (index, preset) in presets.enumerated() {
                if Task.isCancelled { break }
                activity = Activity(title: "Exporting \(index + 1) of \(presets.count)", progress: Double(index) / Double(presets.count))
                var options = capture
                options.apply(preset)
                var look = self.look
                if look.backdrop == .desktop { look.backdrop = .canvas }
                do {
                    let shot = try await render(look: look, capture: options)
                    let url = folder.appending(path: fileName(for: look, sizeName: preset.name, capture: options) + "." + format.fileExtension)
                    try shot.write(to: url, format: format)
                    addShot(shot, file: url)
                    written.append(url)
                } catch is CancellationError {
                    break
                } catch {
                    alert = AlertContent(title: "Couldn’t Export \(preset.name)", message: error.localizedDescription)
                    break
                }
            }
            activity = nil
            applyViewport()
            if !written.isEmpty {
                status = StatusMessage(
                    "Exported \(written.count == 1 ? "1 Image" : "\(written.count) Images")",
                    action: .init("Show in Finder", help: "⇧⌘R") { NSWorkspace.shared.activateFileViewerSelecting(written) }
                )
            }
        }
        exportTask = task
        await task.value
        exportTask = nil
    }

    var canCancel: Bool { exportTask != nil }

    func cancel() {
        exportTask?.cancel()
    }

    private func perform(_ activityTitle: String, failure: String, _ work: @escaping () async throws -> Void) async {
        activity = Activity(title: activityTitle, progress: nil)
        defer { activity = nil }
        do {
            try await work()
        } catch {
            let error = error as? CaptureError
            alert = AlertContent(title: failure, message: [error?.errorDescription, error?.recoverySuggestion].compactMap { $0 }.joined(separator: " "))
        }
    }

    private func addShot(_ shot: RenderedShot, file: URL?) {
        shots.insert(Shot(image: shot.image, pointSize: shot.pointSize, file: file, name: fileName()), at: 0)
    }

    /// The newest shot saved to disk, for Show in Finder.
    var lastSavedFile: URL? { shots.lazy.compactMap(\.file).first }

    func deleteShot(_ shot: Shot) {
        guard let index = shots.firstIndex(of: shot) else { return }
        shots.remove(at: index)
        undoManager?.registerUndo(withTarget: self) { $0.shots.insert(shot, at: min(index, $0.shots.count)) }
        undoManager?.setActionName("Remove Shot")
    }

    // MARK: Looks

    func apply(_ look: Look) {
        setLook(as: "Use \(look.name)") { current in
            // Keep the desktop window where it was when the Look doesn't move it.
            current = look
        }
    }

    func shuffleBackground() {
        guard case .gradient(let name, _) = look.background else { return }
        setLook(as: "Shuffle Background") { $0.background = .gradient(name: name, seed: UInt32.random(in: 1...UInt32.max)) }
    }

    func chooseBackgroundImage() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        guard await panel.present(in: window) == .OK, let url = panel.url else { return }
        setLook(as: "Change Background") { $0.background = .image(path: url.path) }
    }

    var currentLookID: String? {
        Defaults.shared.allLooks.first { $0.matchesStyle(of: look) }?.id
    }
}

// MARK: - Supporting types

struct AlertContent: Identifiable {
    let id = UUID()
    var title: String
    var message: String
}

struct Activity: Equatable {
    var title: String
    /// 0…1, or nil while the length isn't known.
    var progress: Double?
}

enum CanvasZoom: Equatable {
    case fit, actual
}

/// A saved or copied image, kept in the window's shots tray for this session.
struct Shot: Identifiable, Equatable {
    let id = UUID()
    let image: CGImage
    let pointSize: CGSize
    let file: URL?
    let name: String

    static func == (a: Shot, b: Shot) -> Bool { a.id == b.id }
}

private final class NavigationDelegate: NSObject, WKNavigationDelegate {
    weak var model: ShootModel?

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        model?.pageFinishedLoading()
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: any Error) {
        model?.pageFailed(error)
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: any Error) {
        model?.pageFailed(error)
    }
}

extension Look {
    /// Same window, backdrop and background, ignoring name and the desktop window's place.
    func matchesStyle(of other: Look) -> Bool {
        window == other.window && backdrop == other.backdrop && safari == other.safari
            && canvas == other.canvas && background == other.background
    }
}
