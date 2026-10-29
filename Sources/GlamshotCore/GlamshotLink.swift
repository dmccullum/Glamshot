import Foundation

/// The address that opens a page in Glamshot: `glamshot://open?url=<page address>`, for a
/// bookmarklet or another app. Only http and https pages open.
public enum GlamshotLink {
    public static let scheme = "glamshot"

    /// The page a glamshot:// address names, or nil if it isn't one or names something other than
    /// an http or https page.
    public static func page(from link: URL) -> URL? {
        guard link.scheme?.lowercased() == scheme,
              let components = URLComponents(url: link, resolvingAgainstBaseURL: false),
              components.host?.lowercased() == "open",
              let query = components.percentEncodedQuery, query.hasPrefix("url=") else { return nil }
        // Everything after url= is the page, so a hand-typed address with an unencoded & still works.
        var value = String(query.dropFirst(4))
        if let fragment = components.percentEncodedFragment { value += "#" + fragment }
        guard let decoded = value.removingPercentEncoding, let page = URL(string: decoded),
              ["http", "https"].contains(page.scheme?.lowercased()), page.host() != nil else { return nil }
        return page
    }
}
