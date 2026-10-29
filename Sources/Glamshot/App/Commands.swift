import AppKit
import DMKit
import GlamshotCore
import SwiftUI
import WebKit

extension FocusedValues {
    @Entry var shoot: ShootModel?
    @Entry var inspectorShown: Binding<Bool>?
    @Entry var shotsTrayShown: Binding<Bool>?
}

struct GlamshotCommands: Commands {
    @FocusedValue(\.shoot) private var model
    @FocusedValue(\.inspectorShown) private var inspectorShown
    @FocusedValue(\.shotsTrayShown) private var shotsTrayShown
    @Environment(\.openWindow) private var openWindow
    private let recents = RecentPages.shared
    private let safari = SafariBridge.shared

    private var hasPage: Bool { model?.hasPage ?? false }

    var body: some Commands {
        CommandGroup(after: .newItem) {
            Button("Open Location…") { model?.focusAddress() }
                .keyboardShortcut("l")
                .disabled(model == nil)
            Button("Open File…") { Task { await openFile() } }
                .keyboardShortcut("o")
            Menu("Open Recent") {
                ForEach(recents.urls, id: \.self) { url in
                    Button(FileNaming.domain(of: url).map { "\($0) — \(url.path())" } ?? url.lastPathComponent) { open(url) }
                }
                Divider()
                Button("Clear Menu") { recents.clear() }.disabled(recents.urls.isEmpty)
            }
            Divider()
            Button("Open Safari’s Front Page") { Task { await openSafariFrontPage() } }
                .keyboardShortcut("l", modifiers: [.command, .option])
            Menu("Open Safari Tab") {
                if safari.tabs.isEmpty {
                    Button("Read Safari’s Tabs") { Task { await safari.refreshTabs() } }
                } else {
                    ForEach(safari.tabs) { tab in
                        Button(tab.title.isEmpty ? tab.url.absoluteString : tab.title) { open(tab.url) }
                    }
                    Divider()
                    Button("Refresh") { Task { await safari.refreshTabs() } }
                }
            }
        }

        CommandGroup(replacing: .saveItem) {
            Button("Close") { NSApp.keyWindow?.performClose(nil) }
                .keyboardShortcut("w")
            Divider()
            Button("Save Image…") { Task { await model?.saveImage() } }
                .keyboardShortcut("s")
                .disabled(!hasPage)
            Button("Share…") { Task { await model?.share() } }
                .disabled(!hasPage)
            Button("Export Sizes…") { model?.chooseExportSizes() }
                .keyboardShortcut("e", modifiers: [.command, .shift])
                .disabled(!hasPage)
            Divider()
            Button("Show in Finder") {
                if let file = model?.lastSavedFile { NSWorkspace.shared.activateFileViewerSelecting([file]) }
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .disabled(model?.lastSavedFile == nil)
        }

        CommandGroup(replacing: .pasteboard) {
            Button("Cut") { NSApp.sendAction(#selector(NSText.cut(_:)), to: nil, from: nil) }
                .keyboardShortcut("x")
            Button(textHasFocus ? "Copy" : "Copy Image") {
                if textHasFocus {
                    NSApp.sendAction(#selector(NSText.copy(_:)), to: nil, from: nil)
                } else {
                    Task { await model?.copyImage() }
                }
            }
            .keyboardShortcut("c")
            Button("Paste") {
                if textHasFocus {
                    NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: nil)
                } else if let string = NSPasteboard.general.string(forType: .string) {
                    model?.load(string)
                }
            }
            .keyboardShortcut("v")
            Button("Select All") { NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: nil) }
                .keyboardShortcut("a")
            Divider()
            Button("Copy Style") { copyStyle() }
                .keyboardShortcut("c", modifiers: [.command, .option])
                .disabled(model == nil)
            Button("Paste Style") { pasteStyle() }
                .keyboardShortcut("v", modifiers: [.command, .option])
                .disabled(model == nil || StylePasteboard.look == nil)
        }

        CommandGroup(before: .sidebar) {
            Button(inspectorShown?.wrappedValue == true ? "Hide Inspector" : "Show Inspector") {
                inspectorShown?.wrappedValue.toggle()
            }
            .keyboardShortcut("i", modifiers: [.command, .option])
            .disabled(inspectorShown == nil)
            Button(shotsTrayShown?.wrappedValue == true ? "Hide Shots Tray" : "Show Shots Tray") {
                shotsTrayShown?.wrappedValue.toggle()
            }
            .disabled(shotsTrayShown == nil)
            Divider()
            Button("Zoom In") { model?.zoom = .actual }
                .keyboardShortcut("+")
                .disabled(model == nil || model?.zoom == .actual)
            Button("Zoom Out") { model?.zoom = .fit }
                .keyboardShortcut("-")
                .disabled(model == nil || model?.zoom == .fit)
            Button("Zoom to Fit") { model?.zoom = .fit }
                .keyboardShortcut("0")
                .disabled(model == nil || model?.zoom == .fit)
            Divider()
            Toggle("Screen", isOn: Binding(
                get: { model?.capture.fullPage == false },
                set: { _ in model?.setCapture(as: "Turn Off Full Page") { $0.fullPage = false } }
            ))
            .keyboardShortcut("1")
            .disabled(model == nil)
            Toggle("Full Page", isOn: Binding(
                get: { model?.capture.fullPage ?? false },
                set: { _ in model?.setCapture(as: "Turn On Full Page") { $0.fullPage = true } }
            ))
            .keyboardShortcut("2")
            .disabled(model == nil || model?.effectiveLook.backdrop == .desktop)
            Divider()
        }

        CommandMenu("Page") {
            Button("Back") { model?.goBack() }
                .keyboardShortcut("[")
                .disabled(!(model?.canGoBack ?? false))
            Button("Forward") { model?.goForward() }
                .keyboardShortcut("]")
                .disabled(!(model?.canGoForward ?? false))
            Divider()
            Button("Reload Page") { model?.reload() }
                .keyboardShortcut("r")
                .disabled(!hasPage)
            Button("Stop Loading") { model?.stop() }
                .keyboardShortcut(".")
                .disabled(!(model?.isLoading ?? false))
            Button("Refresh Full-Page Preview") { model?.refreshFullPagePreview() }
                .disabled(!hasPage || !(model?.capture.fullPage ?? false))
            Divider()
            Menu("Size") {
                Button("Custom") { model?.chooseCustomSize() }
                Divider()
                ForEach(Defaults.shared.allPresets) { preset in
                    Button(preset.name) { model?.choose(preset) }
                }
            }
            .disabled(model == nil)
            Picker("Page Appearance", selection: Binding(
                get: { model?.capture.appearance ?? .light },
                set: { value in model?.setCapture(as: "Change Page Appearance") { $0.appearance = value } }
            )) {
                ForEach(CaptureOptions.Appearance.allCases, id: \.self) { Text($0.title).tag($0) }
            }
            .disabled(model == nil)
            Toggle("Request Mobile Website", isOn: Binding(
                get: { model?.capture.userAgent == .iPhone },
                set: { value in
                    model?.setCapture(as: value ? "Request Mobile Website" : "Request Desktop Website") { $0.userAgent = value ? .iPhone : .mac }
                }
            ))
            .disabled(model == nil)
            Button("Hide Elements…") { model?.isEditingHiddenElements = true }
                .disabled(model == nil)
            Divider()
            Button("Cancel Export") { model?.cancel() }
                .disabled(!(model?.canCancel ?? false))
            Divider()
            Button("Clear Website Data…") { Task { await clearWebsiteData() } }
        }

        CommandMenu("Frame") {
            ForEach(FrameStyle.allCases, id: \.self) { style in
                Toggle(style.title, isOn: Binding(
                    get: { model?.effectiveLook.frameStyle == style },
                    set: { _ in model?.setFrameStyle(style) }
                ))
                .disabled(!(model?.availableFrameStyles.contains(style) ?? false))
            }
            Toggle("Safari Window on Canvas", isOn: Binding(
                get: { model?.look.window == .safari },
                set: { value in model?.setLook(as: value ? "Show Safari Window" : "Hide Safari Window") { $0.window = value ? .safari : .none } }
            ))
            .disabled(model?.effectiveLook.frameStyle != .canvas)
            Divider()
            Toggle("Auto Padding", isOn: Binding(
                get: { model?.look.canvas.autoPadding ?? false },
                set: { value in
                    model?.setLook(as: value ? "Turn On Auto Padding" : "Turn Off Auto Padding") { $0.canvas.autoPadding = value }
                }
            ))
            .disabled(model?.look.backdrop != .canvas)
            Menu("Background") {
                ForEach(GradientLibrary.entries) { entry in
                    Toggle(entry.name, isOn: Binding(
                        get: { model?.look.background.gradientName == entry.name },
                        set: { _ in model?.setLook(as: "Change Background") { $0.background = .gradient(name: entry.name, seed: 0) } }
                    ))
                }
                Divider()
                Button("Shuffle") { model?.shuffleBackground() }
                    .disabled(model?.look.background.gradientName == nil)
                Button("Image…") { Task { await model?.chooseBackgroundImage() } }
            }
            .disabled(model == nil || model?.look.backdrop == Backdrop.none)
            Button("Center Window") { model?.centerDesktopWindow() }
                .disabled(model?.effectiveLook.backdrop != .desktop)
            Button("Fill Desktop") { model?.fillDesktop() }
                .disabled(model?.effectiveLook.backdrop != .desktop)
            Button("Menu Bar Text…") { model?.isEditingMenuBar = true }
                .disabled(model?.effectiveLook.backdrop != .desktop)
        }

        CommandMenu("Bookmarks") {
            ForEach(safari.folders, id: \.name) { folder in
                Menu(folder.name) {
                    ForEach(folder.bookmarks) { bookmark in
                        Button(bookmark.title) { open(bookmark.url) }
                    }
                }
            }
            if !safari.bookmarks.isEmpty { Divider() }
            Button("Read Safari Bookmarks") { readSafariBookmarks() }
            Button("Import Bookmarks File…") { Task { await importBookmarks() } }
        }
    }

    private func readSafariBookmarks() {
        do {
            try safari.reloadSafariBookmarks()
            model?.status = StatusMessage("Read \(safari.bookmarks.count) Bookmarks")
        } catch {
            let alert = NSAlert()
            alert.messageText = "Couldn’t Read Safari Bookmarks"
            alert.informativeText = error.localizedDescription
            alert.addButton(withTitle: "Open Privacy Settings")
            alert.addButton(withTitle: "Cancel")
            if alert.runModal() == .alertFirstButtonReturn,
               let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles") {
                NSWorkspace.shared.open(url)
            }
        }
    }

    private func importBookmarks() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html]
        panel.message = "Choose a Bookmarks file exported from Safari with File › Export › Bookmarks."
        guard await panel.present(in: NSApp.keyWindow) == .OK, let url = panel.url else { return }
        do {
            try safari.importBookmarks(from: url)
            model?.status = StatusMessage("Imported \(safari.bookmarks.count) Bookmarks")
        } catch {
            model?.alert = AlertContent(title: "Couldn’t Import Bookmarks", message: error.localizedDescription)
        }
    }

    private var textHasFocus: Bool {
        NSApp.keyWindow?.firstResponder is NSText
    }

    private func open(_ url: URL) {
        if let model { model.load(url) } else { PendingOpen.shared.urls.append(url); openWindow(id: "shoot") }
    }

    private func openFile() async {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.html, .webArchive, .internetLocation]
        guard await panel.present(in: NSApp.keyWindow) == .OK, let url = panel.url else { return }
        open(CanvasView.resolved(url))
    }

    private func openSafariFrontPage() async {
        do {
            guard let url = try await safari.frontPageURL() else {
                model?.alert = AlertContent(title: "Couldn’t Open Safari’s Page", message: "Safari has no window open.")
                return
            }
            open(url)
        } catch {
            model?.alert = AlertContent(title: "Couldn’t Open Safari’s Page", message: error.localizedDescription)
        }
    }

    private func copyStyle() {
        guard let model else { return }
        StylePasteboard.look = model.look
        model.status = StatusMessage("Copied Style")
    }

    private func pasteStyle() {
        guard let model, var look = StylePasteboard.look else { return }
        // A style carries the frame, not this window's desktop window placement.
        look.desktop.widthFraction = model.look.desktop.widthFraction
        look.desktop.heightFraction = model.look.desktop.heightFraction
        look.desktop.centerX = model.look.desktop.centerX
        look.desktop.centerY = model.look.desktop.centerY
        model.setLook(as: "Paste Style") { $0 = look }
    }

    private func clearWebsiteData() async {
        let alert = NSAlert()
        alert.messageText = "Clear website data?"
        alert.informativeText = "Cookies, sign-ins and caches for every site in Glamshot are removed. Undo can’t restore them."
        alert.addButton(withTitle: "Clear Website Data")
        alert.addButton(withTitle: "Cancel")
        guard let window = NSApp.keyWindow else { return }
        guard await alert.beginSheetModal(for: window) == .alertFirstButtonReturn else { return }
        let store = WKWebsiteDataStore.default()
        await store.removeData(ofTypes: WKWebsiteDataStore.allWebsiteDataTypes(), modifiedSince: .distantPast)
        model?.status = StatusMessage("Cleared Website Data")
    }
}

/// The style Copy Style put away, for Paste Style in any window.
@MainActor
enum StylePasteboard {
    static var look: Look?
}

/// Pages opened from Finder, the Dock or a menu. The frontmost Glamshot window loads them; with
/// none open, a new window takes them when it appears.
@MainActor
@Observable
final class PendingOpen {
    static let shared = PendingOpen()
    var urls: [URL] = []
    /// Every open shoot, so a page can go to the frontmost one.
    @ObservationIgnored private var shoots: [WeakShoot] = []

    private struct WeakShoot { weak var model: ShootModel? }

    func register(_ model: ShootModel) {
        shoots.removeAll { $0.model == nil || $0.model === model }
        shoots.append(WeakShoot(model: model))
    }

    func unregister(_ model: ShootModel) {
        shoots.removeAll { $0.model == nil || $0.model === model }
    }

    /// The shoot whose window is frontmost.
    var frontmost: ShootModel? {
        let models = shoots.compactMap(\.model)
        for window in NSApp.orderedWindows {
            if let model = models.first(where: { $0.window === window }) { return model }
        }
        return models.last
    }

    func open(_ new: [URL]) {
        guard let first = new.first else { return }
        if let target = frontmost {
            target.load(first)
            target.window?.makeKeyAndOrderFront(nil)
            urls.append(contentsOf: new.dropFirst())
        } else {
            urls.append(contentsOf: new)
            NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        }
    }

    /// The next page to open, removed from the queue.
    func take() -> URL? {
        urls.isEmpty ? nil : urls.removeFirst()
    }
}
