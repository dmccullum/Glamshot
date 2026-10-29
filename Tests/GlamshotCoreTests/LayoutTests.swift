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

    @Test func everyFrameSavesAtTheChosenSize() {
        for style in FrameStyle.allCases {
            var look = Look(name: "Style", window: .safari, backdrop: .canvas)
            look.frameStyle = style
            #expect(FrameLayout.make(output: output, look: look).canvasSize == output, "\(style)")
        }
    }

    @Test func aBarePageIgnoresTheShadow() {
        let layout = FrameLayout.make(output: output, look: Look(name: "Page", window: .none, backdrop: .none, shadow: 0.7))
        #expect(layout.pageRect == CGRect(origin: .zero, size: output))
    }

    @Test func shadowRoomComesOutOfTheImage() {
        let layout = FrameLayout.make(output: output, look: Look(name: "Safari", window: .safari, backdrop: .none, shadow: 1))
        let margin = ChromeMetrics.shadowMargin
        #expect(layout.canvasSize == output)
        #expect(layout.windowRect == CGRect(x: margin, y: margin, width: 1512 - margin * 2, height: 982 - margin * 2))
    }

    @Test func paddingIsEvenOnEverySide() {
        let macBook16 = CGSize(width: 1728, height: 1117)
        let layout = FrameLayout.make(output: macBook16, look: Look(name: "Canvas", window: .safari, backdrop: .canvas))
        let window = layout.windowRect
        let gaps = [window.minX, window.minY, layout.canvasSize.width - window.maxX, layout.canvasSize.height - window.maxY]
        #expect(Set(gaps).count == 1)
        #expect(layout.canvasSize == macBook16)
    }

    @Test func anIPhoneOnACanvasLaysOutInWhatThePaddingLeaves() {
        let phone = CGSize(width: 402, height: 874)
        let look = Look(name: "Canvas", window: .safari, backdrop: .canvas, safari: SafariOptions(device: .iPhone))
        let layout = FrameLayout.make(output: phone, look: look)
        let padding = FrameLayout.automaticPadding(for: phone)
        #expect(layout.canvasSize == phone)
        #expect(layout.pageSize.width == 402 - padding * 2)
    }

    @Test func tabBarAddsItsHeight() {
        var look = Look(name: "Tabs", window: .safari, backdrop: .none, shadow: 0)
        look.safari.showsTabBar = true
        #expect(FrameLayout.make(output: output, look: look).pageRect.height == CGFloat(982 - 52 - 28))
    }

    @Test func aSocialCanvasPadsInsideTheImage() {
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
        let social = CGSize(width: 1080, height: 1350)
        let layout = FrameLayout.make(output: social, look: look)
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

    @Test func desktopWindowIsPaddedEvenlyBelowTheMenuBar() {
        var look = Look(name: "Desktop", window: .safari, backdrop: .desktop)
        look.canvas.autoPadding = false
        look.canvas.padding = 60
        let layout = FrameLayout.make(output: output, look: look)
        #expect(layout.canvasSize == output)
        #expect(layout.windowRect == CGRect(x: 60, y: ChromeMetrics.menuBarHeight + 60,
                                            width: 1512 - 120, height: 982 - ChromeMetrics.menuBarHeight - 120))
    }

    @Test func desktopAutoPaddingMatchesTheCanvas() {
        let look = Look(name: "Desktop", window: .safari, backdrop: .desktop)
        let layout = FrameLayout.make(output: output, look: look)
        let padding = FrameLayout.automaticPadding(for: output)
        #expect(layout.windowRect.minX == padding)
        #expect(layout.windowRect.minY == ChromeMetrics.menuBarHeight + padding)
        #expect(layout.windowRect.maxX == output.width - padding)
        #expect(layout.windowRect.maxY == output.height - padding)
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

    @Test func templateSplitsIntoTextAndTokens() {
        let parts = FileNaming.parts(of: "{domain} — {size} {nope}{date}")
        #expect(parts == [.token(.domain), .text(" — "), .token(.size), .text(" {nope}"), .token(.date)])
        #expect(FileNaming.template(from: parts) == "{domain} — {size} {nope}{date}")
        #expect(FileNaming.parts(of: "") == [])
        #expect(FileNaming.parts(of: "{") == [.text("{")])
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
