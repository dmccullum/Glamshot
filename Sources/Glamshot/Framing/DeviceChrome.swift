import GlamshotCore
import SwiftUI

/// The iPhone and iPad status bar, as in Apple's own screenshots: 9:41, full signal, Wi-Fi and
/// a full battery.
struct StatusBarView: View {
    let device: SafariOptions.Device
    let isDark: Bool
    let width: CGFloat

    private var foreground: Color { isDark ? .white : .black }

    var body: some View {
        Group {
            if device == .iPhone { iPhone } else { iPad }
        }
        .foregroundStyle(foreground)
        .frame(width: width)
        .background(isDark ? Color.black : Color.white)
        .environment(\.colorScheme, isDark ? .dark : .light)
    }

    /// The time sits in the left ear and the icons in the right, either side of the Dynamic Island.
    private var iPhone: some View {
        HStack(spacing: 0) {
            Text("9:41")
                .font(.system(size: 17, weight: .semibold))
                .frame(maxWidth: .infinity)
            Spacer().frame(width: 126)
            HStack(spacing: 6) {
                Image(systemName: "cellularbars")
                Image(systemName: "wifi")
                Image(systemName: "battery.100percent").font(.system(size: 21, weight: .regular))
            }
            .font(.system(size: 15, weight: .semibold))
            .frame(maxWidth: .infinity)
        }
        .padding(.top, 6)
        .frame(height: ChromeMetrics.iPhoneStatusBarHeight)
    }

    private var iPad: some View {
        HStack(spacing: 6) {
            Text("9:41").font(.system(size: 13, weight: .semibold))
            Text("Tue Oct 29").font(.system(size: 13, weight: .regular))
            Spacer(minLength: 0)
            Image(systemName: "wifi").font(.system(size: 12, weight: .semibold))
            Text("100%").font(.system(size: 13, weight: .regular))
            Image(systemName: "battery.100percent").font(.system(size: 17))
        }
        .padding(.horizontal, 20)
        .frame(height: ChromeMetrics.iPadStatusBarHeight)
    }
}

/// Safari on iPad's toolbar: sidebar and back/forward at the left, the address in the middle,
/// Share, New Tab and the tab overview at the right.
struct IPadSafariChrome: View {
    let options: SafariOptions
    let isDark: Bool
    let context: FrameContext
    let width: CGFloat

    private var palette: ChromePalette { isDark ? .dark : .light }

    var body: some View {
        VStack(spacing: 0) {
            StatusBarView(device: .iPad, isDark: isDark, width: width)
                .background(palette.toolbar)
            ZStack {
                HStack(spacing: 22) {
                    symbol("sidebar.left")
                    symbol("chevron.left")
                    symbol("chevron.right").opacity(0.35)
                    Spacer(minLength: 0)
                    symbol("square.and.arrow.up")
                    symbol("plus")
                    symbol("square.on.square")
                }
                .padding(.horizontal, 20)
                AddressCapsule(options: options, isDark: isDark, context: context,
                               width: min(max(width * 0.45, 220), 560), height: 36)
            }
            .frame(height: ChromeMetrics.iPadToolbarHeight)
            if options.showsTabBar {
                Text(context.title.isEmpty ? (context.domain.isEmpty ? "Untitled" : context.domain) : context.title)
                    .font(.system(size: 12))
                    .foregroundStyle(palette.primary)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity)
                    .frame(height: ChromeMetrics.tabBarHeight)
                    .background(palette.tab)
            }
        }
        .frame(width: width)
        .background(palette.toolbar)
        .overlay(alignment: .bottom) { Rectangle().fill(palette.separator).frame(height: 1) }
        .environment(\.colorScheme, isDark ? .dark : .light)
    }

    private func symbol(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 17, weight: .regular))
            .foregroundStyle(Color.accentColor)
    }
}

/// Safari on iPhone's compact address bar as in iOS 27, floating over the bottom of the page above
/// the home indicator: Back, the address, and Tabs (which replaced iOS 26's More button), or the
/// small domain pill Safari shrinks it to after scrolling.
struct PhoneAddressBar: View {
    let options: SafariOptions
    let isDark: Bool
    let context: FrameContext
    let width: CGFloat

    private var palette: ChromePalette { isDark ? .dark : .light }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            switch options.phoneBar {
            case .full: full
            case .minimized: minimized
            }
            Capsule()
                .fill(isDark ? Color.white : Color.black)
                .frame(width: 140, height: 5)
                .padding(.top, options.phoneBar == .full ? 14 : 10)
                .padding(.bottom, 8)
        }
        .frame(width: width)
        .environment(\.colorScheme, isDark ? .dark : .light)
        .allowsHitTesting(false)
    }

    private var full: some View {
        HStack(spacing: 10) {
            circleButton("chevron.left")
            AddressCapsule(options: options, isDark: isDark, context: context,
                           width: width - ChromeMetrics.iPhoneAddressInset * 2 - 2 * (ChromeMetrics.iPhoneAddressHeight + 10),
                           height: ChromeMetrics.iPhoneAddressHeight, elevated: true)
            circleButton("square.on.square")
        }
        .padding(.horizontal, ChromeMetrics.iPhoneAddressInset)
    }

    private var minimized: some View {
        Text(domain)
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(palette.primary)
            .padding(.horizontal, 16)
            .frame(height: 30)
            .background(Capsule().fill(palette.field.opacity(0.96)))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
    }

    private var domain: String {
        options.address == .hidden ? "" : context.domain
    }

    private func circleButton(_ symbol: String) -> some View {
        Image(systemName: symbol)
            .font(.system(size: 18, weight: .medium))
            .foregroundStyle(palette.primary)
            .frame(width: ChromeMetrics.iPhoneAddressHeight, height: ChromeMetrics.iPhoneAddressHeight)
            .background(Circle().fill(palette.field.opacity(0.96)))
            .shadow(color: .black.opacity(0.14), radius: 10, y: 3)
    }
}

/// The rounded address field with the page's domain, shared by iPad and iPhone Safari.
struct AddressCapsule: View {
    let options: SafariOptions
    let isDark: Bool
    let context: FrameContext
    let width: CGFloat
    let height: CGFloat
    var elevated = false

    private var palette: ChromePalette { isDark ? .dark : .light }

    var body: some View {
        HStack(spacing: 6) {
            if context.url?.scheme == "https", options.address != .hidden {
                Image(systemName: "lock.fill").font(.system(size: 11, weight: .semibold)).foregroundStyle(palette.secondary)
            }
            Text(text)
                .font(.system(size: elevated ? 15 : 13, weight: elevated ? .medium : .regular))
                .foregroundStyle(palette.primary)
                .lineLimit(1)
                .truncationMode(.middle)
        }
        .padding(.horizontal, 36)
        .frame(width: max(width, 120), height: height)
        .background(Capsule().fill(elevated ? palette.field.opacity(0.96) : palette.field))
        .overlay(alignment: .leading) {
            Image(systemName: "text.page").font(.system(size: 14)).foregroundStyle(palette.secondary).padding(.leading, 14)
        }
        .overlay(alignment: .trailing) {
            Image(systemName: "arrow.clockwise").font(.system(size: 14)).foregroundStyle(palette.secondary).padding(.trailing, 14)
        }
        .shadow(color: elevated ? .black.opacity(0.14) : .clear, radius: 10, y: 3)
    }

    private var text: String { context.address(options.address) }
}
