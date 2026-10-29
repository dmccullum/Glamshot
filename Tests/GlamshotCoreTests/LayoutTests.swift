import CoreGraphics
import Foundation
import Testing
@testable import GlamshotCore

@Suite("Frame layout")
struct FrameLayoutTests {
    let output = CGSize(width: 1512, height: 982)

    @Test func barePageFillsTheOutput() {
        let layout = FrameLayout.make(output: output, look: Look(name: "Bare", window: .none, backdrop: .none, shadow: 0))
        #expect(layout.canvasSize == output)
        #expect(layout.pageRect == CGRect(origin: .zero, size: output))
    }

    @Test func safariTakesItsChromeFromTheOutput() {
        let layout = FrameLayout.make(output: output, look: Look(name: "Safari", window: .safari, backdrop: .none, shadow: 0))
        #expect(layout.canvasSize == output)
        #expect(layout.windowRect == CGRect(origin: .zero, size: output))
        #expect(layout.pageRect.size == CGSize(width: 1512, height: 982 - ChromeMetrics.toolbarHeight))
    }

    @Test func shadowRoomComesFromTheOutput() {
        let layout = FrameLayout.make(output: output, look: Look(name: "Safari", window: .safari, backdrop: .none, shadow: 1))
        let margin = ChromeMetrics.shadowMargin
        #expect(layout.canvasSize == output)
        #expect(layout.windowRect == CGRect(x: margin, y: margin, width: 1512 - margin * 2, height: 982 - margin * 2))
    }

    @Test func tabBarAddsItsHeight() {
        var look = Look(name: "Tabs", window: .safari, backdrop: .none, shadow: 0)
        look.safari.showsTabBar = true
        #expect(FrameLayout.make(output: output, look: look).pageRect.height == CGFloat(982 - 52 - 28))
    }

    @Test func canvasPadsInsideTheOutput() {
        let social = CGSize(width: 1080, height: 1350)
        let look = Look(name: "Canvas", window: .safari, backdrop: .canvas)
        let layout = FrameLayout.make(output: social, look: look)
        let padding = FrameLayout.automaticPadding(for: social)
        #expect(layout.canvasSize == social)
        #expect(layout.windowRect == CGRect(x: padding, y: padding, width: 1080 - padding * 2, height: 1350 - padding * 2))
    }

    @Test func customPaddingIsKeptBelowThePage() {
        var look = Look(name: "Canvas", window: .none, backdrop: .canvas)
        look.canvas.autoPadding = false
        look.canvas.padding = 10_000
        let layout = FrameLayout.make(output: output, look: look)
        #expect(layout.pageRect.width >= FrameLayout.minimumPageSize.width)
        #expect(layout.pageRect.height >= FrameLayout.minimumPageSize.height)
    }

    @Test func fullPageWidthIsThePagesAndPaddingGoesAround() {
        let look = Look(name: "Canvas", window: .none, backdrop: .canvas)
        let layout = FrameLayout.make(output: output, look: look, pageHeight: 8000)
        let padding = FrameLayout.automaticPadding(for: output)
        #expect(layout.pageRect.size == CGSize(width: 1512, height: 8000))
        #expect(layout.canvasSize == CGSize(width: 1512 + padding * 2, height: 8000 + padding * 2))
        #expect(FrameLayout.pageSize(output: output, look: look, fullPage: true) == output)
    }

    @Test func desktopIsTheOutputAndTheWindowSitsBelowTheMenuBar() {
        var look = Look(name: "Desktop", window: .safari, backdrop: .desktop)
        look.desktop.centerY = 0
        let layout = FrameLayout.make(output: output, look: look)
        #expect(layout.canvasSize == output)
        #expect(layout.windowRect.minY == ChromeMetrics.menuBarHeight)
        #expect(layout.windowRect.width == (1512 * 0.8).rounded())
    }

    @Test func desktopWindowRoundTripsThroughFractions() {
        let look = Look(name: "Desktop", window: .safari, backdrop: .desktop)
        let rect = CGRect(x: 100, y: 120, width: 900, height: 600)
        var moved = look
        moved.desktop = FrameLayout.desktopOptions(look.desktop, with: rect, output: output)
        let layout = FrameLayout.make(output: output, look: moved)
        #expect(abs(layout.windowRect.minX - 100) <= 1 && abs(layout.windowRect.minY - 120) <= 1)
        #expect(abs(layout.windowRect.width - 900) <= 1 && abs(layout.windowRect.height - 600) <= 1)
    }

    @Test func movingNearTheCenterSnapsToIt() {
        let area = CGRect(x: 0, y: 24, width: 1000, height: 600)
        let near = CGRect(x: 205, y: 120, width: 600, height: 400)   // center 505, 320
        let result = FrameLayout.snapToCenter(near, in: area, tolerance: 8)
        #expect(result.x && result.rect.midX == 500)
        #expect(result.y && result.rect.midY == 324)
        let far = CGRect(x: 100, y: 40, width: 600, height: 400)
        let none = FrameLayout.snapToCenter(far, in: area, tolerance: 8)
        #expect(!none.x && !none.y && none.rect == far)
    }

    @Test func draggingAnEdgeInwardAddsPadding() {
        let pull = { (edge: FrameLayout.PaddingEdge, t: CGSize) in
            FrameLayout.draggedPadding(from: 100, edge: edge, translation: t, automatic: 70, limit: 400, tolerance: 6)
        }
        #expect(pull(.leading, CGSize(width: 20, height: 0)).padding == 120)
        #expect(pull(.trailing, CGSize(width: 20, height: 0)).padding == 80)
        #expect(pull(.top, CGSize(width: 0, height: -150)).padding == 0)
        #expect(pull(.bottom, CGSize(width: 0, height: -900)).padding == 400)
    }

    @Test func draggedPaddingSnapsToAuto() {
        let near = FrameLayout.draggedPadding(from: 100, edge: .leading, translation: CGSize(width: -26, height: 0),
                                              automatic: 70, limit: 400, tolerance: 6)
        #expect(near.isAutomatic && near.padding == 70)
        let far = FrameLayout.draggedPadding(from: 100, edge: .leading, translation: CGSize(width: -10, height: 0),
                                             automatic: 70, limit: 400, tolerance: 6)
        #expect(!far.isAutomatic && far.padding == 90)
    }

    @Test func paddingLimitKeepsTheMinimumPage() {
        let limit = FrameLayout.maximumPadding(output: CGSize(width: 1000, height: 600), chrome: 52)
        #expect(limit == 214)   // (600 − 52 − 120) / 2, under (1000 − 200) / 2
        var look = Look(name: "Canvas", window: .safari, backdrop: .canvas)
        look.canvas.autoPadding = false
        look.canvas.padding = limit
        let layout = FrameLayout.make(output: CGSize(width: 1000, height: 600), look: look)
        #expect(layout.pageRect.height == FrameLayout.minimumPageSize.height)
    }

    @Test func desktopWindowFollowsTheOutput() {
        let look = Look(name: "Desktop", window: .safari, backdrop: .desktop)
        let small = FrameLayout.make(output: output, look: look)
        let large = FrameLayout.make(output: CGSize(width: 2560, height: 1440), look: look)
        #expect(large.windowRect.width > small.windowRect.width)
    }
}

@Suite("Safari device")
struct SafariDeviceTests {
    @Test func automaticFollowsTheOutputSize() {
        let options = SafariOptions()
        #expect(options.resolvedDevice(for: CGSize(width: 402, height: 874)) == .iPhone)
        #expect(options.resolvedDevice(for: CGSize(width: 1032, height: 1376)) == .iPad)
        #expect(options.resolvedDevice(for: CGSize(width: 1512, height: 982)) == .mac)
        #expect(options.resolvedDevice(for: CGSize(width: 1080, height: 1350)) == .mac)
        #expect(options.resolvedDevice(for: CGSize(width: 360, height: 780)) == .iPhone)
    }

    @Test func theSizeAlwaysDecides() {
        #expect(SafariOptions(device: .mac).resolvedDevice(for: CGSize(width: 402, height: 874)) == .iPhone)
    }

    @Test func iPhoneTakesOnlyTheStatusBar() {
        let look = Look(name: "Phone", window: .safari, backdrop: .none, safari: SafariOptions(device: .iPhone), shadow: 0)
        let layout = FrameLayout.make(output: CGSize(width: 402, height: 874), look: look)
        #expect(layout.pageRect == CGRect(x: 0, y: ChromeMetrics.iPhoneStatusBarHeight, width: 402, height: 874 - ChromeMetrics.iPhoneStatusBarHeight))
    }
}

@Suite("Frame style")
struct FrameStyleTests {
    @Test func eachStyleRoundTrips() {
        for style in FrameStyle.allCases {
            var look = Look(name: "Test")
            look.frameStyle = style
            #expect(look.frameStyle == style)
        }
    }

    @Test func canvasKeepsTheWindowChoice() {
        var look = Look(name: "Test", window: .none, backdrop: .none)
        look.frameStyle = .canvas
        #expect(look.window == .none)
        look.frameStyle = .desktop
        #expect(look.window == .safari)
    }
}

@Suite("File naming")
struct FileNamingTests {
    @Test func defaultTemplate() {
        let context = FileNaming.Context(url: URL(string: "https://www.apple.com/mac/"), sizeName: "MacBook Pro 14\"", width: 1512, height: 982)
        #expect(FileNaming.name(FileNaming.defaultTemplate, context) == "apple.com — MacBook Pro 14”")
    }

    @Test func slashesAndColonsAreReplaced() {
        let context = FileNaming.Context(url: nil, title: "A/B: C", sizeName: "", width: 1, height: 1)
        #expect(FileNaming.name("{title}", context) == "A-B- C")
    }

    @Test func emptyNameFallsBack() {
        let context = FileNaming.Context(url: nil, sizeName: "", width: 1, height: 1)
        #expect(FileNaming.name("{domain} — {size}", context) == "Glamshot")
    }
}

@Suite("Capture options")
struct CaptureOptionsTests {
    @Test func hiddenSelectorsBecomeOneRule() {
        let options = CaptureOptions(hiddenSelectors: "#cookie-banner\n.chat-widget, header .promo")
        #expect(options.hidingStylesheet == "#cookie-banner, .chat-widget, header .promo { visibility: hidden !important; }")
        #expect(CaptureOptions().hidingStylesheet == nil)
    }

    @Test func applyingAPhoneUsesTheIPhoneAgent() {
        var options = CaptureOptions()
        options.apply(SizePreset.builtIns.first { $0.group == .phone }!)
        #expect(options.userAgent == .iPhone)
        #expect(options.scale == 3)
    }

    @Test func presetIDsAreUnique() {
        #expect(Set(SizePreset.builtIns.map(\.id)).count == SizePreset.builtIns.count)
    }
}
