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

    /// The full page's height in points, when one has been measured.
    private var fullPageHeight: CGFloat? {
        model.capture.fullPage ? model.fullPagePreview?.pointSize.height : nil
    }

    var body: some View {
        GeometryReader { proxy in
            let layout = FrameLayout.make(output: model.capture.outputSize, look: model.look, pageHeight: fullPageHeight)
            let available = CGSize(width: max(proxy.size.width - 48, 1), height: max(proxy.size.height - 48, 1))
            let fit = min(available.width / layout.canvasSize.width, available.height / layout.canvasSize.height, 1)
            let scale = model.zoom == .actual ? 1 : fit
            let shown = CGSize(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)

            ScrollView([.horizontal, .vertical]) {
                ZStack(alignment: .topLeading) {
                    ShotView(layout: layout, look: model.look, context: model.frameContext) {
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
                        livePage(layout: layout, scale: scale)
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
        }
        .background(Color(nsColor: .underPageBackgroundColor))
        .dropTarget(for: URL.self, isTargeted: $isDropTargeted) { urls, _ in
            guard let url = urls.first else { return false }
            model.load(Self.resolved(url))
            return true
        }
    }

    private func livePage(layout: FrameLayout, scale: CGFloat) -> some View {
        let rect = layout.pageRect
        let radius = (model.look.window == .safari ? ChromeMetrics.cornerRadius
                      : model.look.backdrop == .none ? 0 : model.look.canvas.cornerRadius) * scale
        return WebHost(webView: model.webView, viewport: model.pageSize, bottomCornerRadius: radius,
                       topCornerRadius: model.look.window == .safari ? 0 : radius)
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
