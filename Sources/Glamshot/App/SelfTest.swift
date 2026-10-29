import AppKit
import GlamshotCore
import WebKit

/// `Glamshot --self-test <fixtures>`: photographs the fixture pages inside the running app
/// (WebKit can't run under `swift test`), checks sizes and pixel colors, prints the results and
/// quits with 0 when everything passed.
@MainActor
enum SelfTest {
    private static var failures = 0
    private static var checks = 0

    static func run(fixtures: URL) async {
        let red = Pixel(r: 255, g: 0, b: 0), blue = Pixel(r: 0, g: 0, b: 255)

        for scale in 1...3 {
            let stage = await Stage(fixtures.appending(path: "bands.html"), viewport: CGSize(width: 800, height: 600))
            if let capture = await attempt("viewport \(scale)×", { try await stage.photographer.capture(
                CaptureOptions(width: 800, height: 600, scale: scale, delay: 0)) }) {
                check("viewport \(scale)× width", capture.image.width == 800 * scale, "\(capture.image.width)")
                check("viewport \(scale)× height", capture.image.height == 600 * scale, "\(capture.image.height)")
                check("viewport \(scale)× first band", capture.image.pixel(x: 10, y: 498 * scale) == red, "\(capture.image.pixel(x: 10, y: 498 * scale))")
                check("viewport \(scale)× second band", capture.image.pixel(x: 10, y: 502 * scale) == blue, "\(capture.image.pixel(x: 10, y: 502 * scale))")
            }
            if let capture = await attempt("full page \(scale)×", { try await stage.photographer.capture(
                CaptureOptions(width: 800, height: 600, scale: scale, fullPage: true, delay: 0)) }) {
                check("full page \(scale)× height", capture.image.height == 5000 * scale, "\(capture.image.height)")
                for band in 0..<10 {
                    let expected = band.isMultiple(of: 2) ? red : blue
                    let top = capture.image.pixel(x: 400 * scale, y: (band * 500 + 3) * scale)
                    let bottom = capture.image.pixel(x: 400 * scale, y: (band * 500 + 496) * scale)
                    check("full page \(scale)× band \(band)", top == expected && bottom == expected, "\(top) / \(bottom)")
                }
                check("full page \(scale)× restores the frame", stage.webView.frame.size == CGSize(width: 800, height: 600), "\(stage.webView.frame.size)")
            }
            stage.close()
        }

        // Lazy images, script-loaded images and fade-ins below the fold all appear in a full page.
        let green = Pixel(r: 0, g: 255, b: 0)
        let lazy = await Stage(fixtures.appending(path: "lazy.html"), viewport: CGSize(width: 800, height: 600))
        if let capture = await attempt("lazy content", { try await lazy.photographer.capture(
            CaptureOptions(width: 800, height: 600, scale: 1, fullPage: true, delay: 0)) }) {
            check("lazy content page height", capture.image.height == 6600, "\(capture.image.height)")
            for (name, top) in [("native lazy image", 1500), ("script-loaded image", 3200), ("fade-in block", 4900)] {
                let pixel = capture.image.pixel(x: 200, y: top + 100)
                check(name, pixel == green, "\(pixel)")
            }
        }
        lazy.close()

        // A window behind other apps (here, ordered out) still finishes a full-page capture.
        let hidden = await Stage(fixtures.appending(path: "bands.html"), viewport: CGSize(width: 800, height: 600))
        hidden.window.orderOut(nil)
        if let capture = await attempt("hidden window full page", { try await hidden.photographer.capture(
            CaptureOptions(width: 800, height: 600, scale: 1, fullPage: true, delay: 0)) }) {
            check("hidden window full page height", capture.image.height == 5000, "\(capture.image.height)")
        }
        hidden.close()

        let hero = await Stage(fixtures.appending(path: "hero.html"), viewport: CGSize(width: 1512, height: 982))
        if let capture = await attempt("100vh hero", { try await hero.photographer.capture(
            CaptureOptions(width: 1512, height: 982, scale: 1, fullPage: true, delay: 0)) }) {
            check("100vh hero page height", capture.pointSize.height == 982 + 2000, "\(capture.pointSize.height)")
            check("100vh hero keeps its height", capture.image.pixel(x: 100, y: 978) == red && capture.image.pixel(x: 100, y: 986) == blue,
                  "\(capture.image.pixel(x: 100, y: 978)) / \(capture.image.pixel(x: 100, y: 986))")
        }
        hero.close()

        // The Shortcuts action's path: an off-screen shoot framed in a canvas Look.
        let look = Look.builtIns.first { $0.id == "safari-canvas" }!
        let options = CaptureOptions(width: 800, height: 600, scale: 2, delay: 0)
        if let shot = await attempt("headless shoot", {
            let shoot = try await HeadlessShoot(url: fixtures.appending(path: "bands.html"),
                                                viewport: FrameLayout.pageSize(output: options.outputSize, look: look))
            defer { shoot.close() }
            return try await shoot.model.render(look: look, capture: options)
        }) {
            let layout = FrameLayout.make(output: options.outputSize, look: look)
            check("headless shoot size", shot.image.width == Int(layout.canvasSize.width) * 2 && shot.image.height == Int(layout.canvasSize.height) * 2,
                  "\(shot.image.width) × \(shot.image.height)")
            let pageCenter = CGPoint(x: layout.pageRect.minX + 10, y: layout.pageRect.minY + 100)
            check("headless shoot page pixels", shot.image.pixel(x: Int(pageCenter.x) * 2, y: Int(pageCenter.y) * 2) == red,
                  "\(shot.image.pixel(x: Int(pageCenter.x) * 2, y: Int(pageCenter.y) * 2))")
        }

        print("Self-test: \(checks - failures) of \(checks) checks passed.")
        exit(failures == 0 ? 0 : 1)
    }

    private static func attempt<T>(_ name: String, _ work: () async throws -> T) async -> T? {
        do {
            return try await work()
        } catch {
            checks += 1
            failures += 1
            print("✘ \(name): \(error)")
            return nil
        }
    }

    private static func check(_ name: String, _ passed: Bool, _ detail: String) {
        checks += 1
        if passed {
            print("✔ \(name)")
        } else {
            failures += 1
            print("✘ \(name): \(detail)")
        }
    }

    /// An offscreen window holding a web view at a viewport size.
    final class Stage {
        let window: NSWindow
        let webView: WKWebView
        let photographer: PagePhotographer

        init(_ page: URL, viewport: CGSize) async {
            let configuration = WKWebViewConfiguration()
            configuration.preferences.inactiveSchedulingPolicy = .none
            webView = WKWebView(frame: CGRect(origin: .zero, size: viewport), configuration: configuration)
            window = NSWindow(contentRect: CGRect(origin: .zero, size: viewport), styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            let container = NSView(frame: CGRect(origin: .zero, size: viewport))
            container.addSubview(webView)
            window.contentView = container
            window.alphaValue = 0.01
            window.orderFrontRegardless()
            photographer = PagePhotographer(webView: webView)
            webView.loadFileURL(page, allowingReadAccessTo: page.deletingLastPathComponent())
            let start = Date.now
            repeat { try? await Task.sleep(for: .milliseconds(50)) } while webView.isLoading && Date.now.timeIntervalSince(start) < 10
        }

        func close() { window.close() }
    }
}

struct Pixel: Equatable, CustomStringConvertible {
    var r, g, b: UInt8
    var description: String { "rgb(\(r), \(g), \(b))" }
}

extension CGImage {
    /// The pixel at x, y from the top left, with each channel snapped to 0 or 255 when close.
    func pixel(x: Int, y: Int) -> Pixel {
        var data = [UInt8](repeating: 0, count: 4)
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: &data, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4, space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.draw(self, in: CGRect(x: -x, y: y - height + 1, width: width, height: height))
        func snap(_ value: UInt8) -> UInt8 { value > 230 ? 255 : value < 25 ? 0 : value }
        return Pixel(r: snap(data[0]), g: snap(data[1]), b: snap(data[2]))
    }
}
