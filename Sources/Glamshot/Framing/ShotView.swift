import AppKit
import GlamshotCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// What the frame needs to know about the page besides its pixels.
struct FrameContext {
    var url: URL?
    var title: String
    /// Dark appearance: the page's prefers-color-scheme, and Safari's chrome and status bar.
    var isDark: Bool
    /// The Custom address text.
    var customAddress: String = ""
    /// The color along the page's top edge, for Safari on iPhone's status bar.
    var pageTopColor: NSColor? = nil

    /// What the address field shows for an address setting.
    func address(_ setting: SafariOptions.Address) -> String {
        switch setting {
        case .hidden: return ""
        case .custom: return customAddress
        case .fullURL: return url?.absoluteString ?? ""
        case .domain: return url.flatMap(FileNaming.domain(of:)) ?? url?.lastPathComponent ?? ""
        }
    }

    /// The domain for the minimized iPhone pill and tab titles.
    var domain: String {
        customAddress.isEmpty ? (url.flatMap(FileNaming.domain(of:)) ?? "") : customAddress
    }
}

/// A finished shot: backdrop, window and page, laid out in points. The window shows it scaled
/// to fit with the live page in place of `page`; saving draws it with the photographed page.
struct ShotView<Page: View>: View {
    let layout: FrameLayout
    let look: Look
    let context: FrameContext
    /// False when the window draws the live page itself and lays the iPhone address bar over it.
    var drawsPageOverlay = true
    @ViewBuilder let page: () -> Page

    private var chromeIsDark: Bool { Self.chromeIsDark(look: look, context: context) }

    static func chromeIsDark(look: Look, context: FrameContext) -> Bool {
        context.isDark
    }

    /// Light menu bar text over a dark background, dark over a light one, as macOS does.
    private var menuBarHasLightText: Bool { look.background.topIsDark }

    private var cornerRadius: CGFloat { Self.cornerRadius(look: look, layout: layout) }

    /// A Mac window is always rounded; an iPhone or iPad screen only when it sits inside the image,
    /// so a full-size screenshot keeps square corners for a device mockup.
    static func cornerRadius(look: Look, layout: FrameLayout) -> CGFloat {
        let isInset = layout.windowRect != CGRect(origin: .zero, size: layout.canvasSize)
        switch (look.window, look.backdrop) {
        case (.safari, _):
            switch look.safari.device {
            case .iPhone: return isInset ? ChromeMetrics.iPhoneScreenRadius : 0
            case .iPad: return isInset ? ChromeMetrics.iPadScreenRadius : 0
            case .mac, .automatic: return ChromeMetrics.cornerRadius
            }
        case (.none, .none): return 0
        case (.none, _): return look.canvas.cornerRadius
        }
    }

    private var shadowStrength: CGFloat { min(max(look.shadow, 0), 1) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if look.backdrop != .none {
                BackgroundView(fill: look.background)
                    .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                    .clipped()
            }
            if look.backdrop == .desktop {
                MenuBarView(options: look.desktop, lightText: menuBarHasLightText)
                    .frame(width: layout.canvasSize.width)
            }
            window
                .frame(width: layout.windowRect.width, height: layout.windowRect.height)
                .offset(x: layout.windowRect.minX, y: layout.windowRect.minY)
        }
        .frame(width: layout.canvasSize.width, height: layout.canvasSize.height, alignment: .topLeading)
        .clipped()
    }

    /// The window at its real size, scaled into its place: a device screen in a canvas is drawn
    /// whole and shrunk, so its chrome stays in proportion to the page.
    private var window: some View {
        let scale = layout.windowScale
        let natural = CGSize(width: layout.windowRect.width / scale, height: layout.windowRect.height / scale)
        let shape = RoundedRectangle(cornerRadius: cornerRadius * scale, style: .continuous)
        return VStack(spacing: 0) {
            if look.window == .safari {
                switch look.safari.device {
                case .iPhone:
                    StatusBarView(device: .iPhone, isDark: chromeIsDark, width: natural.width, pageColor: context.pageTopColor)
                case .iPad:
                    IPadSafariChrome(options: look.safari, isDark: chromeIsDark, context: context, width: natural.width)
                case .mac, .automatic:
                    SafariChromeView(options: look.safari, isDark: chromeIsDark, context: context, width: natural.width)
                }
            }
            page()
                .frame(width: layout.pageSize.width, height: layout.pageSize.height)
                .clipped()
                .overlay {
                    if drawsPageOverlay, look.window == .safari, look.safari.device == .iPhone {
                        PhoneAddressBar(options: look.safari, isDark: chromeIsDark, context: context, width: layout.pageSize.width)
                    }
                }
        }
        .frame(width: natural.width, height: natural.height, alignment: .top)
        .scaleEffect(scale, anchor: .topLeading)
        .frame(width: layout.windowRect.width, height: layout.windowRect.height, alignment: .topLeading)
        .clipShape(shape)
        .overlay {
            if look.window == .safari, look.safari.device == .mac {
                shape.strokeBorder(chromeIsDark ? Color.white.opacity(0.14) : Color.black.opacity(0.12), lineWidth: 1)
            }
        }
        .background {
            if shadowStrength > 0 {
                shape.fill(.black)
                    .shadow(color: .black.opacity(0.38 * shadowStrength), radius: ChromeMetrics.shadowRadius * shadowStrength,
                            y: ChromeMetrics.shadowOffset * shadowStrength)
                    .shadow(color: .black.opacity(0.18 * shadowStrength), radius: 2, y: 1)
            }
        }
    }
}

/// A rendered shot at full resolution.
struct RenderedShot {
    let image: CGImage
    let scale: Int
    let wasCut: Bool

    var pointSize: CGSize { CGSize(width: image.width / scale, height: image.height / scale) }

    func data(format: ImageFormat) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, format.contentType.identifier as CFString, 1, nil) else { return nil }
        let dpi = 72 * scale
        var properties: [CFString: Any] = [kCGImagePropertyDPIWidth: dpi, kCGImagePropertyDPIHeight: dpi]
        if format != .png { properties[kCGImageDestinationLossyCompressionQuality] = Defaults.shared.jpegQuality }
        let image = format.supportsTransparency ? image : (flattened() ?? image)
        CGImageDestinationAddImage(destination, image, properties as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    func write(to url: URL, format: ImageFormat) throws {
        guard let data = data(format: format) else { throw CocoaError(.fileWriteUnknown) }
        try data.write(to: url, options: .atomic)
    }

    /// The image on white, for formats without transparency.
    private func flattened() -> CGImage? {
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil, width: image.width, height: image.height, bitsPerComponent: 8, bytesPerRow: 0,
                                      space: space, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue) else { return nil }
        context.setFillColor(.white)
        context.fill(CGRect(x: 0, y: 0, width: image.width, height: image.height))
        context.draw(image, in: CGRect(x: 0, y: 0, width: image.width, height: image.height))
        return context.makeImage()
    }
}

enum ShotRenderer {
    /// Frames a photographed page at the photograph's scale.
    @MainActor
    static func render(page: PageCapture, look: Look, output: CGSize, fullPage: Bool, context: FrameContext) async throws -> CGImage {
        var context = context
        context.pageTopColor = page.image.topEdgeColor() ?? context.pageTopColor
        let layout = FrameLayout.make(output: output, look: look, pageHeight: fullPage ? page.pointSize.height : nil)
        var background: CGImage?
        if look.backdrop != .none, case .gradient(let name, let seed) = look.background {
            let scale = CGFloat(page.scale)
            background = try await GradientCache.render(
                name: name, seed: seed,
                pixelSize: CGSize(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)
            )
        }
        let view = ShotView(layout: layout, look: look, context: context) {
            Image(decorative: page.image, scale: CGFloat(page.scale))
                .resizable()
                .interpolation(.high)
        }
        .environment(\.colorScheme, .light)
        .environment(\.renderedBackground, background)
        let renderer = ImageRenderer(content: view)
        renderer.scale = CGFloat(page.scale)
        renderer.proposedSize = ProposedViewSize(layout.canvasSize)
        renderer.isOpaque = look.backdrop != .none
        guard let image = renderer.cgImage else { throw CaptureError.imageTooLarge }
        return image
    }
}

extension CGImage {
    /// The average color of the top two rows, or nil if it can't be read.
    func topEdgeColor() -> NSColor? {
        let sampleWidth = 64
        var data = [UInt8](repeating: 0, count: sampleWidth * 2 * 4)
        guard let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: &data, width: sampleWidth, height: 2, bitsPerComponent: 8, bytesPerRow: sampleWidth * 4,
                                      space: space, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        // Draw the whole image squeezed to 64 pixels wide, top rows in view.
        let scale = CGFloat(sampleWidth) / CGFloat(width)
        context.interpolationQuality = .medium
        context.draw(self, in: CGRect(x: 0, y: 2 - CGFloat(height) * scale, width: CGFloat(sampleWidth), height: CGFloat(height) * scale))
        var r = 0, g = 0, b = 0
        for i in stride(from: 0, to: data.count, by: 4) { r += Int(data[i]); g += Int(data[i + 1]); b += Int(data[i + 2]) }
        let n = CGFloat(data.count / 4) * 255
        return NSColor(srgbRed: CGFloat(r) / n, green: CGFloat(g) / n, blue: CGFloat(b) / n, alpha: 1)
    }
}
