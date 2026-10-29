import Foundation

/// Names saved images from a template such as “{domain} — {size}”.
public enum FileNaming {
    public static let defaultTemplate = "{domain} — {size}"

    /// What a template can fill in. Settings shows each as a chip; the template stores “{domain}”.
    public enum Token: String, CaseIterable, Sendable {
        case domain, title, size, dimensions, frame, date

        public var placeholder: String { "{\(rawValue)}" }

        public var title: String {
            switch self {
            case .domain: "Domain"
            case .title: "Page Title"
            case .size: "Size"
            case .dimensions: "Dimensions"
            case .frame: "Frame"
            case .date: "Date"
            }
        }
    }

    /// A run of typed text or a token, in template order.
    public enum Part: Equatable, Sendable {
        case text(String)
        case token(Token)
    }

    /// Splits a template into text and tokens. Braces that don't name a token stay text.
    public static func parts(of template: String) -> [Part] {
        var parts: [Part] = []
        var text = ""
        var rest = Substring(template)
        while !rest.isEmpty {
            if rest.first == "{", let close = rest.firstIndex(of: "}"),
               let token = Token(rawValue: String(rest[rest.index(after: rest.startIndex)..<close])) {
                if !text.isEmpty { parts.append(.text(text)); text = "" }
                parts.append(.token(token))
                rest = rest[rest.index(after: close)...]
            } else {
                text.append(rest.removeFirst())
            }
        }
        if !text.isEmpty { parts.append(.text(text)) }
        return parts
    }

    /// Joins parts back into a template, merging neighbouring text.
    public static func template(from parts: [Part]) -> String {
        parts.map { part in
            switch part {
            case .text(let text): text
            case .token(let token): token.placeholder
            }
        }.joined()
    }

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
