import Foundation

/// Names saved images from a template such as “{domain} — {size}”.
public enum FileNaming {
    public static let defaultTemplate = "{domain} — {size}"

    /// The tokens a template can use, for Settings.
    public static let tokens = ["{domain}", "{title}", "{size}", "{dimensions}", "{frame}", "{date}"]

    public struct Context: Sendable {
        public var url: URL?
        public var title: String
        public var sizeName: String
        public var width: Int
        public var height: Int
        /// The window and backdrop, such as “Safari on Canvas”.
        public var frameName: String
        public var date: Date

        public init(url: URL?, title: String = "", sizeName: String, width: Int, height: Int, frameName: String = "", date: Date = .now) {
            self.url = url
            self.title = title
            self.sizeName = sizeName
            self.width = width
            self.height = height
            self.frameName = frameName
            self.date = date
        }
    }

    /// The file name without extension. Characters Finder can't show are replaced, and an empty
    /// result falls back to “Glamshot”.
    public static func name(_ template: String, _ context: Context) -> String {
        let domain = context.url.flatMap(domain(of:)) ?? context.url?.lastPathComponent ?? ""
        let date = context.date.formatted(.iso8601.year().month().day())
        var result = template
        for (token, value) in [
            ("{domain}", domain), ("{title}", context.title), ("{size}", context.sizeName),
            ("{dimensions}", "\(context.width)×\(context.height)"), ("{frame}", context.frameName), ("{date}", date)
        ] {
            result = result.replacingOccurrences(of: token, with: value)
        }
        result = result
            .replacingOccurrences(of: "/", with: "-")
            .replacingOccurrences(of: ":", with: "-")
            .replacingOccurrences(of: "\"", with: "”")
            .trimmingCharacters(in: CharacterSet(charactersIn: " —-.").union(.whitespacesAndNewlines))
        while result.contains("  ") { result = result.replacingOccurrences(of: "  ", with: " ") }
        return result.isEmpty ? "Glamshot" : result
    }

    /// “apple.com” for https://www.apple.com/mac/.
    public static func domain(of url: URL) -> String? {
        guard let host = url.host(), !host.isEmpty else { return nil }
        return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
    }
}
