import CoreGraphics
import Foundation
import Testing
@testable import GlamshotCore

@Suite("Frame layout")
struct FrameLayoutTests {
    let page = CGSize(width: 1512, height: 982)

    @Test func barePageIsThePage() {
        let layout = FrameLayout.make(page: page, look: Look(name: "Bare", window: .none, backdrop: .none))
        #expect(layout.canvasSize == page)
        #expect(layout.pageRect == CGRect(origin: .zero, size: page))
    }

    @Test func safariAddsChromeAndShadowRoom() {
        let layout = FrameLayout.make(page: page, look: Look(name: "Safari", window: .safari, backdrop: .none))
        let margin = ChromeMetrics.shadowMargin
        #expect(layout.chromeHeight == ChromeMetrics.toolbarHeight)
        #expect(layout.canvasSize == CGSize(width: 1512 + margin * 2, height: 982 + 52 + margin * 2))
        #expect(layout.pageRect.minY == margin + 52)
        #expect(layout.pageRect.size == page)
    }

    @Test func tabBarAddsItsHeight() {
        var look = Look(name: "Tabs", window: .safari, backdrop: .none)
        look.safari.showsTabBar = true
        look.safari.showsShadow = false
        let layout = FrameLayout.make(page: page, look: look)
        #expect(layout.canvasSize.height == CGFloat(982 + 52 + 28))
    }

    @Test func canvasHonorsTheRatio() {
        for aspect in AspectRatio.allCases where aspect != .auto {
            let look = Look(name: "Canvas", window: .safari, backdrop: .canvas, canvas: CanvasOptions(aspect: aspect, autoBalance: false))
            let layout = FrameLayout.make(page: page, look: look)
            let ratio = layout.canvasSize.width / layout.canvasSize.height
            #expect(abs(ratio - aspect.value!) < 0.01, "\(aspect.title)")
            // Nothing is cut without Auto Balance.
            #expect(CGRect(origin: .zero, size: layout.canvasSize).contains(layout.windowRect))
        }
    }

    @Test func autoBalanceLetsATallPageBleedOffTheBottom() {
        let tall = CGSize(width: 1512, height: 8000)
        let look = Look(name: "Canvas", window: .safari, backdrop: .canvas, canvas: CanvasOptions(aspect: .r4x5, autoBalance: true))
        let layout = FrameLayout.make(page: tall, look: look)
        let padding = FrameLayout.balancedPadding(for: CGSize(width: 1512, height: 8052))
        #expect(layout.canvasSize.width == 1512 + padding * 2)
        #expect(layout.windowRect.minY == padding)
        #expect(layout.windowRect.maxY > layout.canvasSize.height)
    }

    @Test func autoBalanceCentersAWidePage() {
        let look = Look(name: "Canvas", window: .safari, backdrop: .canvas, canvas: CanvasOptions(aspect: .r1x1, autoBalance: true))
        let layout = FrameLayout.make(page: page, look: look)
        let below = layout.canvasSize.height - layout.windowRect.maxY
        #expect(abs(layout.windowRect.minY - below) <= 1)
    }

    @Test func desktopWindowStaysBelowTheMenuBar() {
        var look = Look(name: "Desktop", window: .safari, backdrop: .desktop)
        look.desktop.centerY = 0
        look.desktop.windowSize = CGSize(width: 900, height: 600)
        let layout = FrameLayout.make(page: .zero, look: look)
        #expect(layout.canvasSize == SizePreset.macBookPro14.size)
        #expect(layout.windowRect.minY == ChromeMetrics.menuBarHeight)
        #expect(FrameLayout.desktopViewport(for: look) == CGSize(width: 900, height: 600 - 52))
    }

    @Test func desktopWindowCannotOutgrowTheDesktop() {
        var look = Look(name: "Desktop", window: .safari, backdrop: .desktop)
        look.desktop.windowSize = CGSize(width: 5000, height: 5000)
        let layout = FrameLayout.make(page: .zero, look: look)
        #expect(layout.windowRect.width == 1512)
        #expect(layout.windowRect.height == 982 - ChromeMetrics.menuBarHeight)
    }

    @Test func alignmentGridUnits() {
        #expect(CanvasAlignment.topLeading.unit == CGPoint(x: 0, y: 0))
        #expect(CanvasAlignment.center.unit == CGPoint(x: 0.5, y: 0.5))
        #expect(CanvasAlignment.bottomTrailing.unit == CGPoint(x: 1, y: 1))
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
