import GlamshotCore
import SwiftUI

/// Safari 26's toolbar (and, optionally, one tab), drawn flat at `ChromeMetrics` sizes.
struct SafariChromeView: View {
    let options: SafariOptions
    let isDark: Bool
    let context: FrameContext
    let width: CGFloat

    private var palette: ChromePalette { isDark ? .dark : .light }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            if options.showsTabBar { tabBar }
        }
        .frame(width: width)
        .background(palette.toolbar)
        .overlay(alignment: .bottom) {
            Rectangle().fill(palette.separator).frame(height: 1)
        }
        .environment(\.colorScheme, isDark ? .dark : .light)
    }

    private var toolbar: some View {
        ZStack {
            HStack(spacing: 0) {
                TrafficLights()
                    .padding(.leading, ChromeMetrics.trafficLightInset - ChromeMetrics.trafficLightDiameter / 2)
                HStack(spacing: 18) {
                    symbol("sidebar.left")
                    HStack(spacing: 14) {
                        symbol("chevron.left")
                        symbol("chevron.right").opacity(0.35)
                    }
                }
                .padding(.leading, 26)
                Spacer(minLength: 0)
                HStack(spacing: 18) {
                    symbol("square.and.arrow.up")
                    symbol("plus")
                    symbol("square.on.square")
                }
                .padding(.trailing, 20)
            }
            addressField
        }
        .frame(height: ChromeMetrics.toolbarHeight)
    }

    private var addressWidth: CGFloat {
        min(max(width * ChromeMetrics.addressWidthFraction, ChromeMetrics.addressMinimumWidth), ChromeMetrics.addressMaximumWidth)
    }

    @ViewBuilder private var addressField: some View {
        if options.address != .hidden, width >= 560 {
            HStack(spacing: 6) {
                if context.url?.scheme == "https" {
                    Image(systemName: "lock.fill").font(.system(size: 10, weight: .semibold)).foregroundStyle(palette.secondary)
                }
                Text(addressText)
                    .font(.system(size: 13, weight: .regular))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
            .padding(.horizontal, 40)
            .frame(width: addressWidth, height: ChromeMetrics.addressHeight)
            .background(Capsule().fill(palette.field))
            .overlay(alignment: .leading) {
                symbol("text.page").padding(.leading, 14).font(.system(size: 13))
            }
            .overlay(alignment: .trailing) {
                symbol("arrow.clockwise").padding(.trailing, 14).font(.system(size: 13))
            }
        }
    }

    private var addressText: String { context.address(options.address) }

    private var tabBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "globe").font(.system(size: 11)).foregroundStyle(palette.secondary)
            Text(context.title.isEmpty ? (context.domain.isEmpty ? "Untitled" : context.domain) : context.title)
                .font(.system(size: 12))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
        }
        .padding(.horizontal, 24)
        .frame(maxWidth: .infinity)
        .frame(height: ChromeMetrics.tabBarHeight)
        .background(palette.tab)
        .overlay(alignment: .top) { Rectangle().fill(palette.separator).frame(height: 1) }
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: ChromeMetrics.toolbarSymbolSize, weight: .regular))
            .foregroundStyle(palette.secondary)
    }
}

/// Close, minimize and zoom.
struct TrafficLights: View {
    var body: some View {
        HStack(spacing: ChromeMetrics.trafficLightSpacing - ChromeMetrics.trafficLightDiameter) {
            light(Color(red: 1, green: 0.373, blue: 0.341))
            light(Color(red: 0.996, green: 0.737, blue: 0.180))
            light(Color(red: 0.157, green: 0.784, blue: 0.251))
        }
    }

    private func light(_ color: Color) -> some View {
        Circle()
            .fill(color)
            .overlay(Circle().strokeBorder(.black.opacity(0.12), lineWidth: 0.5))
            .frame(width: ChromeMetrics.trafficLightDiameter, height: ChromeMetrics.trafficLightDiameter)
    }
}

struct ChromePalette {
    var toolbar: Color
    var field: Color
    var tab: Color
    var separator: Color
    var primary: Color
    var secondary: Color

    static let light = ChromePalette(
        toolbar: Color(white: 0.965), field: Color(white: 0.905), tab: Color(white: 0.93),
        separator: Color(white: 0, opacity: 0.09), primary: Color(white: 0.12), secondary: Color(white: 0.38)
    )
    static let dark = ChromePalette(
        toolbar: Color(red: 0.165, green: 0.169, blue: 0.188), field: Color(red: 0.235, green: 0.24, blue: 0.262),
        tab: Color(red: 0.2, green: 0.204, blue: 0.224),
        separator: Color(white: 1, opacity: 0.08), primary: Color(white: 0.93), secondary: Color(white: 0.66)
    )
}
