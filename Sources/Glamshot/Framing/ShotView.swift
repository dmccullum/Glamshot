import AppKit
import GlamshotCore
import ImageIO
import SwiftUI
import UniformTypeIdentifiers

/// What the frame needs to know about the page besides its pixels.
struct FrameContext {
    var url: URL?
    var title: String
    var pageIsDark: Bool
}

/// A finished shot: backdrop, window and page, laid out in points. The window shows it scaled
/// to fit with the live page in place of `page`; saving draws it with the photographed page.
struct ShotView<Page: View>: View {
    let layout: FrameLayout
    let look: Look
    let context: FrameContext
    @ViewBuilder let page: () -> Page

    private var chromeIsDark: Bool {
        switch look.safari.appearance {
        case .light: false
        case .dark: true
        case .matchPage: context.pageIsDark
        }
    }

    private var menuBarHasLightText: Bool {
        switch look.desktop.menuBar {
        case .automatic: look.background.topIsDark
        case .light: false
        case .dark: true
        }
    }

    private var cornerRadius: CGFloat {
        switch (look.window, look.backdrop) {
        case (.safari, _): ChromeMetrics.cornerRadius
        case (.none, .none): 0
        case (.none, _): look.canvas.cornerRadius
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

    private var window: some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        return VStack(spacing: 0) {
            if look.window == .safari {
                SafariChromeView(options: look.safari, isDark: chromeIsDark, url: context.url,
                                 title: context.title, width: layout.windowRect.width)
            }
            page()
                .frame(width: layout.pageRect.width, height: layout.pageRect.height)
                .clipped()
        }
        .clipShape(shape)
        .overlay {
            if look.window == .safari {
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
    static func render(page: PageCapture, look: Look, context: FrameContext) async throws -> CGImage {
        let layout = FrameLayout.make(page: page.pointSize, look: look)
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
