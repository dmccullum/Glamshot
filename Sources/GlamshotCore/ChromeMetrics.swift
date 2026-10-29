import CoreGraphics

/// Safari 26's window chrome in points, measured from a Safari window at 2×. Drawn at the
/// capture's scale, never stretched to the page, so the chrome keeps its real size next to it.
public enum ChromeMetrics {
    public static let toolbarHeight: CGFloat = 52
    public static let tabBarHeight: CGFloat = 28
    public static let cornerRadius: CGFloat = 16

    public static let trafficLightDiameter: CGFloat = 12
    /// Center to center.
    public static let trafficLightSpacing: CGFloat = 20
    /// From the window's left edge to the first light's center.
    public static let trafficLightInset: CGFloat = 26

    public static let addressHeight: CGFloat = 36
    /// The address capsule's share of the toolbar width, between the limits below.
    public static let addressWidthFraction: CGFloat = 0.5
    public static let addressMinimumWidth: CGFloat = 220
    public static let addressMaximumWidth: CGFloat = 640
    public static let toolbarSymbolSize: CGFloat = 15

    /// The window shadow: blur radius and downward offset at full strength.
    public static let shadowRadius: CGFloat = 40
    public static let shadowOffset: CGFloat = 18
    /// Transparent room around a shadowed window so the shadow isn't cut off.
    public static let shadowMargin: CGFloat = 72

    public static func chromeHeight(showsTabBar: Bool) -> CGFloat {
        toolbarHeight + (showsTabBar ? tabBarHeight : 0)
    }

    /// The macOS 26 menu bar.
    public static let menuBarHeight: CGFloat = 24
}
