import GlamshotCore
import SwiftUI

/// A macOS 26 menu bar: transparent over the desktop, with Safari's menus and the standard
/// status items.
struct MenuBarView: View {
    let options: DesktopOptions
    let lightText: Bool

    private static let menus = ["File", "Edit", "View", "History", "Bookmarks", "Develop", "Window", "Help"]

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 20) {
                Image(systemName: "apple.logo").font(.system(size: 15, weight: .medium))
                Text(options.appName).font(.system(size: 13, weight: .bold))
                ForEach(Self.menus, id: \.self) { Text($0).font(.system(size: 13)) }
            }
            .padding(.leading, 20)
            Spacer(minLength: 0)
            HStack(spacing: 18) {
                Image(systemName: "wifi").font(.system(size: 13, weight: .semibold))
                Image(systemName: "magnifyingglass").font(.system(size: 13, weight: .semibold))
                Image(systemName: "switch.2").font(.system(size: 13, weight: .semibold))
                Text(options.clock).font(.system(size: 13)).monospacedDigit()
            }
            .padding(.trailing, 16)
        }
        .foregroundStyle(lightText ? Color.white : Color.black.opacity(0.88))
        .shadow(color: lightText ? .black.opacity(0.18) : .clear, radius: 1, y: 0.5)
        .frame(height: ChromeMetrics.menuBarHeight)
        .frame(maxWidth: .infinity)
    }
}
