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

    // MARK: Settings

    var capture: CaptureOptions { didSet { captureDidChange(from: oldValue) } }
    var look: Look { didSet { lookDidChange(from: oldValue) } }
    /// Sizes checked for Export Sizes….
    var exportSizeIDs: Set<String> = [SizePreset.macBookPro14.id] {
        didSet { UserDefaults.standard.set(Array(exportSizeIDs), forKey: "exportSizeIDs") }
    }
    /// The Export Sizes sheet is up.
    var isChoosingExportSizes = false
    /// The Hide Elements sheet is up.
    var isEditingHiddenElements = false

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

    /// False for a shoot that shouldn't change the app's remembered settings (a Shortcuts run).
    @ObservationIgnored private let remembersSettings: Bool

    init(rememberingSettings: Bool = true) {
        remembersSettings = rememberingSettings
        let configuration = WKWebViewConfiguration()
        configuration.websiteDataStore = .default()
        configuration.preferences.isElementFullscreenEnabled = true
        // Keep timers and drawing running while the window is behind other apps, so a capture
        // started from the menu or Shortcuts finishes.
        configuration.preferences.inactiveSchedulingPolicy = .none
        configuration.userContentController.addUserScript(WKUserScript(
            source: Self.hidingScriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .defaultClient
        ))
        webView = WKWebView(frame: CGRect(origin: .zero, size: CaptureOptions().outputSize), configuration: configuration)
        webView.allowsBackForwardNavigationGestures = true
        webView.allowsMagnification = false
        webView.isInspectable = true
        photographer = PagePhotographer(webView: webView)

        let defaults = Defaults.shared
        capture = defaults.capture
        look = defaults.look
        webView.customUserAgent = capture.userAgent.string
        webView.appearance = NSAppearance(named: capture.appearance == .dark ? .darkAqua : .aqua)
        if let saved = UserDefaults.standard.stringArray(forKey: "exportSizeIDs") { exportSizeIDs = Set(saved) }
        if rememberingSettings { customAddress = UserDefaults.standard.string(forKey: "customAddress") ?? "" }
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

    /// The page's top edge color, for the iPhone status bar in the window.
    private(set) var pageTopColor: NSColor?

    /// Samples the top of the live page a moment after it changes.
    func refreshPageTopColor() {
        Task {
            try? await Task.sleep(for: .milliseconds(400))
            let configuration = WKSnapshotConfiguration()
            configuration.rect = CGRect(x: 0, y: 0, width: webView.bounds.width, height: 2)
            configuration.snapshotWidth = 64
            guard let image = try? await webView.takeSnapshot(configuration: configuration) else { return }
            var rect = CGRect(origin: .zero, size: image.size)
            pageTopColor = image.cgImage(forProposedRect: &rect, context: nil, hints: nil)?.topEdgeColor()
        }
    }

    fileprivate func pageFinishedLoading() {
        refreshPageTopColor()
        applyHiddenSelectors()
        if capture.fullPage { refreshFullPagePreview() }
    }

    fileprivate func pageFailed(_ error: any Error) {
        let error = error as NSError
        guard error.code != NSURLErrorCancelled else { return }
        alert = AlertContent(title: "Couldn’t Load Page", message: error.localizedDescription)
    }

    // MARK: Capture settings

    /// The preset matching the output size, if any.
    var currentPreset: SizePreset? {
        let matches = Defaults.shared.allPresets.filter { capture.matches($0) }
        // Two devices can share a size (iPhone 17 and 17 Pro); keep the one that was picked.
        return matches.first { $0.id == chosenPresetID } ?? matches.first
    }

    @ObservationIgnored private var chosenPresetID: String?

    var sizeName: String {
        currentPreset?.name ?? "\(capture.width) × \(capture.height)"
    }

    /// Size › Custom: the last custom size, or the current one when there's none.
    var isCustomSize: Bool { currentPreset == nil }

    func chooseCustomSize() {
        guard !isCustomSize else { return }
        chosenPresetID = nil
        let size = Defaults.shared.customSize
        setCapture(as: "Choose Custom Size") {
            $0.width = Int(size.width)
            $0.height = Int(size.height)
        }
        // A remembered custom size can match a preset; nudge it so Custom stays chosen.
        if currentPreset != nil { capture.width += 1 }
        focusSizeRequest += 1
    }

    /// Bumped to put the cursor in the width field.
    var focusSizeRequest = 0

    func choose(_ preset: SizePreset) {
        chosenPresetID = preset.id
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
        if capture.outputSize != old.outputSize, currentPreset == nil, remembersSettings {
            Defaults.shared.customSize = capture.outputSize
        }
        if capture.outputSize != old.outputSize || capture.zoom != old.zoom || capture.fullPage != old.fullPage { applyViewport() }
        if capture.fullPage != old.fullPage || capture.outputSize != old.outputSize || capture.zoom != old.zoom
            || capture.scale != old.scale {
            fullPagePreview = nil
            if capture.fullPage { refreshFullPagePreview() }
        }
        if remembersSettings { Defaults.shared.capture = capture }
    }

    private func lookDidChange(from old: Look) {
        if look.resolved(for: capture.outputSize).backdrop == .desktop, capture.fullPage { capture.fullPage = false }
        if pageSize(for: look) != pageSize(for: old) {
            applyViewport()
            fullPagePreview = nil
            if capture.fullPage { refreshFullPagePreview() }
        }
        if remembersSettings { Defaults.shared.look = look }
    }

    /// The look with its Safari device worked out for this output: iPhone chrome on iPhone sizes.
    var effectiveLook: Look { look.resolved(for: capture.outputSize, fullPage: capture.fullPage) }

    /// The page's room in points: the output minus the window chrome and the backdrop.
    var pageSize: CGSize { pageSize(for: look) }

    func pageSize(for look: Look, output: CGSize? = nil) -> CGSize {
        let output = output ?? capture.outputSize
        return FrameLayout.pageSize(output: output, look: look.resolved(for: output, fullPage: capture.fullPage),
                                    fullPage: capture.fullPage)
    }

    /// The page's layout size in CSS pixels: its room divided by the zoom.
    var layoutSize: CGSize {
        CGSize(width: (pageSize.width / capture.zoom).rounded(), height: (pageSize.height / capture.zoom).rounded())
    }

    /// Sizes the web view to the page's room and zooms it. The host view scales it to fit the window.
    func applyViewport() {
        webView.setFrameSize(pageSize)
        webView.pageZoom = capture.zoom
        Self.applyViewportInsets(to: webView, for: effectiveLook)
        refreshPageTopColor()
    }

    /// Safari on iPhone's bottom bar floats over the page. Its small viewport (svh) stops above
    /// the bar, so a 100svh hero ends there, while the page keeps drawing underneath, as on a phone.
    static func applyViewportInsets(to webView: WKWebView, for look: Look) {
        let bottom = look.window == .safari && look.safari.device == .iPhone ? ChromeMetrics.iPhoneBottomBarInset : 0
        webView.setMinimumViewportInset(NSEdgeInsets(), maximumViewportInset: NSEdgeInsets(top: 0, left: 0, bottom: bottom, right: 0))
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

    // MARK: Frame

    /// The frames this size and mode allow: a full page has no window, and a desktop is a Mac's.
    var availableFrameStyles: [FrameStyle] {
        if capture.fullPage { return [.page, .canvas] }
        if look.resolved(for: capture.outputSize).safari.device != .mac { return [.page, .safari, .canvas] }
        return FrameStyle.allCases
    }

    func setFrameStyle(_ style: FrameStyle) {
        setLook(as: "Change Frame") { $0.frameStyle = style }
    }

    /// The desktop window's outer size in points. Setting it resizes around the window's center.
    var desktopWindowSize: CGSize {
        get { FrameLayout.make(output: capture.outputSize, look: effectiveLook).windowRect.size }
        set {
            let layout = FrameLayout.make(output: capture.outputSize, look: effectiveLook)
            let center = CGPoint(x: layout.windowRect.midX, y: layout.windowRect.midY)
            let rect = CGRect(x: center.x - newValue.width / 2, y: center.y - newValue.height / 2,
                              width: newValue.width, height: newValue.height)
            look.desktop = FrameLayout.desktopOptions(look.desktop, with: rect, output: capture.outputSize)
        }
    }

    /// The menu bar text editor is up.
    var isEditingMenuBar = false

    /// The canvas padding actually used: the automatic amount or the custom one.
    var effectivePadding: CGFloat {
        look.canvas.autoPadding ? FrameLayout.automaticPadding(for: capture.outputSize) : look.canvas.padding
    }

    /// The desktop window's width as a share of the desktop. Setting it scales the window evenly.
    var desktopWindowScale: Double {
        get { look.desktop.widthFraction }
        set {
            let ratio = look.desktop.heightFraction / max(look.desktop.widthFraction, 0.01)
            let width = min(max(newValue, 0.3), 1)
            look.desktop.widthFraction = width
            look.desktop.heightFraction = min(max(width * ratio, 0.3), 1)
        }
    }

    func centerDesktopWindow() {
        setLook(as: "Center Window") {
            $0.desktop.centerX = 0.5
            $0.desktop.centerY = 0.5
        }
    }

    /// Fills the desktop below the menu bar, leaving a 24 pt margin like a zoomed window.
    func fillDesktop() {
        let area = CGSize(width: capture.outputSize.width, height: capture.outputSize.height - ChromeMetrics.menuBarHeight)
        setLook(as: "Fill Desktop") {
            $0.desktop.widthFraction = max((area.width - 48) / area.width, 0.5)
            $0.desktop.heightFraction = max((area.height - 48) / area.height, 0.5)
            $0.desktop.centerX = 0.5
            $0.desktop.centerY = 0.5
        }
    }

    // MARK: Full-page preview

    func refreshFullPagePreview() {
        guard hasPage, capture.fullPage, !isLoading else { return }
        Task {
            var options = capture
            options.scale = 1
            options.delay = Defaults.shared.waitAfterLoading
            fullPagePreview = try? await photographer.capture(options)
        }
    }

    // MARK: Rendering

    /// Photographs the page and frames it at full resolution.
    func render(look: Look? = nil, capture: CaptureOptions? = nil) async throws -> RenderedShot {
        let look = look ?? self.look
        var options = capture ?? self.capture
        if look.resolved(for: options.outputSize).backdrop == .desktop { options.fullPage = false }
        options.delay = Defaults.shared.waitAfterLoading

        // Lay the page out in the room this look leaves in this output, then put the view back.
        let room = FrameLayout.pageSize(output: options.outputSize, look: look.resolved(for: options.outputSize, fullPage: options.fullPage),
                                        fullPage: options.fullPage)
        let original = (size: webView.frame.size, zoom: webView.pageZoom)
        webView.setFrameSize(room)
        webView.pageZoom = options.zoom
        Self.applyViewportInsets(to: webView, for: look.resolved(for: options.outputSize, fullPage: options.fullPage))
        defer {
            webView.setFrameSize(original.size)
            webView.pageZoom = original.zoom
            Self.applyViewportInsets(to: webView, for: effectiveLook)
        }
        let page = try await photographer.capture(options)
        let image = try await ShotRenderer.render(
            page: page, look: look.resolved(for: options.outputSize, fullPage: options.fullPage), output: options.outputSize,
            fullPage: options.fullPage, context: frameContext
        )
        return RenderedShot(image: image, scale: options.scale, wasCut: page.wasCut)
    }

    var frameContext: FrameContext {
        FrameContext(url: url, title: title, isDark: capture.appearance == .dark, customAddress: customAddress,
                     pageTopColor: pageTopColor)
    }

    /// The address a Custom address field shows, such as a production domain over a staging page.
    var customAddress = "" {
        didSet { if remembersSettings { UserDefaults.standard.set(customAddress, forKey: "customAddress") } }
    }

    /// The backdrop the Backdrop switch turns back on.
    var lastBackdrop: Backdrop {
        look.backdrop != .none ? look.backdrop : (Backdrop(rawValue: UserDefaults.standard.string(forKey: "lastBackdrop") ?? "") ?? .canvas)
    }

    func setBackdrop(_ backdrop: Backdrop) {
        if backdrop != .none { UserDefaults.standard.set(backdrop.rawValue, forKey: "lastBackdrop") }
        setLook(as: backdrop == .none ? "Turn Off Backdrop" : "Change Backdrop") { $0.backdrop = backdrop }
    }

    /// Bumped to start editing the address shown in the window mockup.
    var addressEditRequest = 0

    func fileName(for look: Look? = nil, sizeName: String? = nil, capture: CaptureOptions? = nil) -> String {
        let options = capture ?? self.capture
        return FileNaming.name(Defaults.shared.fileNameTemplate, FileNaming.Context(
            url: url, title: title, sizeName: sizeName ?? self.sizeName,
            width: options.width, height: options.height, frameName: (look ?? self.look).summary
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

    func chooseExportSizes() {
        guard hasPage else { return }
        isChoosingExportSizes = true
    }

    /// Renders the shot to a temporary file and offers it to the share menu, at the window's top right.
    func share() async {
        guard hasPage, let window, let content = window.contentView else { return }
        await perform("Preparing Image", failure: "Couldn’t Share Image") {
            let shot = try await self.render()
            let format = Defaults.shared.format
            let folder = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let file = folder.appending(path: self.fileName() + "." + format.fileExtension)
            try shot.write(to: file, format: format)
            let picker = NSSharingServicePicker(items: [file])
            let top = content.isFlipped ? content.bounds.minY + 8 : content.bounds.maxY - 8
            let anchor = CGRect(x: content.bounds.maxX - 60, y: top, width: 1, height: 1)
            picker.show(relativeTo: anchor, of: content, preferredEdge: .minY)
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
                let look = self.look
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

