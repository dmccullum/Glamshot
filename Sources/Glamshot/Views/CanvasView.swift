import AppKit
import DMKit
import GlamshotCore
import SwiftUI
import UniformTypeIdentifiers
import WebKit

/// The shot as it will be saved, scaled to fit, with the live page in the window.
struct CanvasView: View {
    @Bindable var model: ShootModel
    @State private var isDropTargeted = false
    @State private var isEditingAddress = false

    /// The full page's height in points, when one has been measured.
    private var fullPageHeight: CGFloat? {
        model.capture.fullPage ? model.fullPagePreview?.pointSize.height : nil
    }

    var body: some View {
        GeometryReader { proxy in
            let look = model.effectiveLook
            let layout = FrameLayout.make(output: model.capture.outputSize, look: look, pageHeight: fullPageHeight)
            let available = CGSize(width: max(proxy.size.width - 48, 1), height: max(proxy.size.height - 48, 1))
            let fit = min(available.width / layout.canvasSize.width, available.height / layout.canvasSize.height, 1)
            let scale = model.zoom == .actual ? 1 : fit
            let shown = CGSize(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    ShotView(layout: layout, look: look, context: model.frameContext, drawsPageOverlay: false) {
                        if model.capture.fullPage, let preview = model.fullPagePreview {
                            Image(decorative: preview.image, scale: 1).resizable()
                        } else {
                            Color.clear
                        }
                    }
                    .scaleEffect(scale, anchor: .topLeading)
                    .frame(width: shown.width, height: shown.height, alignment: .topLeading)
                    .allowsHitTesting(false)

                    if !(model.capture.fullPage && model.fullPagePreview != nil) {
                        livePage(layout: layout, look: look, scale: scale)
                    }
                    if look.window == .safari, look.safari.device == .iPhone {
                        // Above the live page, as Safari's bar floats over it.
                        PhoneAddressBar(options: look.safari, isDark: ShotView<EmptyView>.chromeIsDark(look: look, context: model.frameContext),
                                        context: model.frameContext, width: layout.pageRect.width)
                            .frame(width: layout.pageRect.width, height: layout.pageRect.height)
                            .scaleEffect(scale, anchor: .topLeading)
                            .frame(width: layout.pageRect.width * scale, height: layout.pageRect.height * scale, alignment: .topLeading)
                            .offset(x: layout.pageRect.minX * scale, y: layout.pageRect.minY * scale)
                    }
                    if look.window == .safari, look.safari.address != .hidden, let rect = addressRect(layout: layout, look: look) {
                        Color.clear
                            .contentShape(Capsule())
                            .frame(width: rect.width * scale, height: rect.height * scale)
                            .offset(x: rect.minX * scale, y: rect.minY * scale)
                            .onTapGesture { isEditingAddress = true }
                            .help("Edit the Address Shown in the Window")
                            .popover(isPresented: $isEditingAddress) { AddressEditor(model: model) }
                    }
                    if model.look.backdrop == .desktop {
                        DesktopWindowHandles(model: model, layout: layout, scale: scale)
                    }
                }
                .frame(width: shown.width, height: shown.height, alignment: .topLeading)
                .contextMenu { CanvasMenu(model: model) }
                .onDrag { dragItem() }
                .padding(24)
                .frame(minWidth: proxy.size.width, minHeight: proxy.size.height)
            }
            .scrollDisabled(model.zoom == .fit)
            .overlay(alignment: .top) { fullPageCapsule.padding(.top, 12) }
            .overlay(alignment: .bottom) { captureModeBar.padding(.bottom, DMLayout.overlayMargin) }
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .dropTarget(for: URL.self, isTargeted: $isDropTargeted) { urls, _ in
            guard let url = urls.first else { return false }
            model.load(Self.resolved(url))
            return true
        }
    }

    /// Where the address field sits in the window mockup, for clicking to edit it.
    private func addressRect(layout: FrameLayout, look: Look) -> CGRect? {
        let window = layout.windowRect
        switch look.safari.device {
        case .mac, .automatic:
            guard window.width >= 560 else { return nil }
            let width = min(max(window.width * ChromeMetrics.addressWidthFraction, ChromeMetrics.addressMinimumWidth), ChromeMetrics.addressMaximumWidth)
            return CGRect(x: window.midX - width / 2, y: window.minY + (ChromeMetrics.toolbarHeight - ChromeMetrics.addressHeight) / 2,
                          width: width, height: ChromeMetrics.addressHeight)
        case .iPad:
            let width = min(max(window.width * 0.45, 220), 560)
            return CGRect(x: window.midX - width / 2, y: window.minY + ChromeMetrics.iPadStatusBarHeight + 7, width: width, height: 36)
        case .iPhone:
            let page = layout.pageRect
            let height = look.safari.phoneBar == .full ? ChromeMetrics.iPhoneAddressHeight : 30
            let width = look.safari.phoneBar == .full ? page.width - 160 : 160
            return CGRect(x: page.midX - width / 2, y: page.maxY - height - (look.safari.phoneBar == .full ? 27 : 23), width: width, height: height)
        }
    }

    private func livePage(layout: FrameLayout, look: Look, scale: CGFloat) -> some View {
        let rect = layout.pageRect
        let radius = ShotView<EmptyView>.cornerRadius(look: look, layout: layout) * scale
        return WebHost(webView: model.webView, viewport: model.pageSize, bottomCornerRadius: radius,
                       topCornerRadius: look.window == .safari ? 0 : radius)
            .frame(width: rect.width * scale, height: min(rect.height, model.pageSize.height) * scale)
            .offset(x: rect.minX * scale, y: rect.minY * scale)
            .opacity(model.hasPage ? 1 : 0)
            .overlay {
                if !model.hasPage {
                    EmptyPageView(model: model)
                        .frame(width: rect.width * scale, height: rect.height * scale)
                        .offset(x: rect.minX * scale, y: rect.minY * scale)
                }
            }
    }

    /// One screen or the whole page: the choice that decides most of the rest, so it floats over
    /// the canvas where it's always in reach.
    private var captureModeBar: some View {
        FloatingBar {
            Picker("Capture", selection: Binding(
                get: { model.capture.fullPage },
                set: { value in model.setCapture(as: value ? "Turn On Full Page" : "Turn Off Full Page") { $0.fullPage = value } }
            )) {
                Text("Screen").tag(false)
                Text("Full Page").tag(true)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .disabled(model.look.backdrop == .desktop)
            .help(model.look.backdrop == .desktop
                  ? "A desktop shows one screen. Turn off the desktop backdrop for a full page."
                  : "One screen at the output size, or the page’s full length (⌥⌘F)")
        }
    }

    @ViewBuilder private var fullPageCapsule: some View {
        if model.capture.fullPage, model.hasPage {
            HStack(spacing: 8) {
                if let preview = model.fullPagePreview {
                    Text("Full page: \(Int(preview.pointSize.width)) × \(Int(preview.pointSize.height))").monospacedDigit()
                } else {
                    ProgressView().controlSize(.small)
                    Text("Measuring the page…")
                }
            }
            .font(.callout)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .floatingGlass(in: Capsule())
        }
    }

    private func dragItem() -> NSItemProvider {
        let provider = NSItemProvider()
        let name = model.fileName() + ".png"
        provider.suggestedName = name
        provider.registerFileRepresentation(forTypeIdentifier: UTType.png.identifier, fileOptions: [], visibility: .all) { completion in
            Task { @MainActor in
                do {
                    let shot = try await model.render()
                    let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: name)
                    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
                    try shot.write(to: url, format: .png)
                    completion(url, false, nil)
                } catch {
                    completion(nil, false, error)
                }
            }
            return nil
        }
        return provider
    }

    /// A dropped .webloc opens the page it points to.
    static func resolved(_ url: URL) -> URL {
        guard url.isFileURL, url.pathExtension == "webloc",
              let data = try? Data(contentsOf: url),
              let plist = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any],
              let string = plist["URL"] as? String, let target = URL(string: string) else { return url }
        return target
    }
}

/// Shown in the page area before anything has loaded.
struct EmptyPageView: View {
    let model: ShootModel

    var body: some View {
        VStack(spacing: 12) {
            Text("Type a web address or drop a link to photograph it")
                .font(.title3)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Open Location…") { model.focusAddress() }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .textBackgroundColor))
    }
}

/// Hosts the live web view. The web view keeps the page's size in points and this view scales it
/// to fit, so the page lays out exactly as it will be photographed.
struct WebHost: NSViewRepresentable {
    let webView: WKWebView
    let viewport: CGSize
    let bottomCornerRadius: CGFloat
    let topCornerRadius: CGFloat

    func makeNSView(context: Context) -> HostView {
        let host = HostView()
        host.wantsLayer = true
        host.layer?.masksToBounds = true
        host.addSubview(webView)
        return host
    }

    func updateNSView(_ host: HostView, context: Context) {
        if webView.superview !== host { host.addSubview(webView) }
        host.viewport = viewport
        host.layer?.cornerRadius = max(bottomCornerRadius, topCornerRadius)
        var corners: CACornerMask = []
        if bottomCornerRadius > 0 { corners.formUnion([.layerMinXMinYCorner, .layerMaxXMinYCorner]) }
        if topCornerRadius > 0 { corners.formUnion([.layerMinXMaxYCorner, .layerMaxXMaxYCorner]) }
        host.layer?.maskedCorners = corners
        host.needsLayout = true
    }

    final class HostView: NSView {
        var viewport: CGSize = .zero

        override var isFlipped: Bool { true }

        override func layout() {
            super.layout()
            guard viewport.width > 0, frame.width > 0 else { return }
            // Bounds in viewport points, frame in window points: AppKit scales drawing and events.
            let scale = frame.width / viewport.width
            setBoundsSize(CGSize(width: frame.width / scale, height: frame.height / scale))
            setBoundsOrigin(.zero)
        }
    }
}

/// The canvas context menu, in the family's order.
struct CanvasMenu: View {
    let model: ShootModel

    var body: some View {
        Button("Save Image…") { Task { await model.saveImage() } }
        Button("Show in Finder") {
            if let file = model.lastSavedFile { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        }
        .disabled(model.lastSavedFile == nil)
        Divider()
        Button("Copy Image") { Task { await model.copyImage() } }
        Divider()
        Button("Export Sizes…") { model.chooseExportSizes() }
        Divider()
        Button("Reload Page") { model.reload() }
    }
}

/// Edits the address the window mockup shows.
struct AddressEditor: View {
    @Bindable var model: ShootModel
    @State private var text = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Address Shown in the Window").font(.headline)
            TextField("yourbrand.com", text: $text)
                .textFieldStyle(.roundedBorder)
                .frame(width: 260)
                .onSubmit(commit)
            HStack {
                Button("Use Page’s Address") {
                    model.setLook(as: "Show Page’s Address") { $0.safari.address = .domain }
                    dismiss()
                }
                Spacer()
                Button("Done", action: commit).keyboardShortcut(.defaultAction)
            }
        }
        .padding(14)
        .onAppear { text = model.customAddress.isEmpty ? model.frameContext.address(.domain) : model.customAddress }
    }

    private func commit() {
        model.customAddress = text.trimmingCharacters(in: .whitespaces)
        model.setLook(as: "Change Address") { $0.safari.address = .custom }
        dismiss()
    }
}
