import AppKit
import Foundation
import Observation

/// Reads Safari's open pages over Apple Events and its bookmarks from disk. macOS asks once for
/// permission to control Safari; the bookmarks file needs Full Disk Access, or an exported
/// Bookmarks.html instead.
@Observable
final class SafariBridge {
    static let shared = SafariBridge()

    struct Tab: Identifiable, Hashable {
        var id: String { url.absoluteString + title }
        let title: String
        let url: URL
    }

    struct Bookmark: Identifiable, Hashable, Codable {
        var id: String { url.absoluteString + title }
        let title: String
        let url: URL
        let folder: String
    }

    enum BridgeError: LocalizedError {
        case script(String)
        case bookmarksUnreadable

        var errorDescription: String? {
            switch self {
            case .script(let message): message
            case .bookmarksUnreadable:
                "Glamshot can’t read Safari’s bookmarks without Full Disk Access. Give it access in System Settings › Privacy & Security › Full Disk Access, or export them from Safari with File › Export › Bookmarks and import that file."
            }
        }
    }

    private(set) var tabs: [Tab] = []
    private(set) var bookmarks: [Bookmark]

    private init() {
        bookmarks = UserDefaults.standard.data(forKey: "importedBookmarks")
            .flatMap { try? JSONDecoder().decode([Bookmark].self, from: $0) } ?? []
        if let fromSafari = try? Self.readSafariBookmarks() { bookmarks = fromSafari }
    }

    // MARK: Tabs

    func frontPageURL() async throws -> URL? {
        let result = try run("""
            tell application "Safari"
                if (count of windows) is 0 then return ""
                return URL of current tab of front window
            end tell
            """)
        return result.stringValue.flatMap(URL.init(string:))
    }

    func refreshTabs() async {
        guard let result = try? run("""
            tell application "Safari"
                set output to {}
                repeat with w in windows
                    repeat with t in tabs of w
                        set end of output to (name of t) & tab & (URL of t)
                    end repeat
                end repeat
                return output
            end tell
            """) else { return }
        var found: [Tab] = []
        for index in stride(from: 1, through: result.numberOfItems, by: 1) {
            guard let line = result.atIndex(index)?.stringValue else { continue }
            let parts = line.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let url = URL(string: String(parts[1])), url.scheme?.hasPrefix("http") == true else { continue }
            found.append(Tab(title: String(parts[0]), url: url))
        }
        tabs = found
    }

    private func run(_ source: String) throws -> NSAppleEventDescriptor {
        var error: NSDictionary?
        guard let script = NSAppleScript(source: source) else { throw BridgeError.script("The script couldn’t be compiled.") }
        let result = script.executeAndReturnError(&error)
        if let error {
            let number = error[NSAppleScript.errorNumber] as? Int
            if number == -1743 {
                throw BridgeError.script("Glamshot isn’t allowed to control Safari. Turn it on in System Settings › Privacy & Security › Automation.")
            }
            throw BridgeError.script(error[NSAppleScript.errorMessage] as? String ?? "Safari didn’t respond.")
        }
        return result
    }

    // MARK: Bookmarks

    /// Re-reads Safari's bookmarks file.
    func reloadSafariBookmarks() throws {
        bookmarks = try Self.readSafariBookmarks()
    }

    static func readSafariBookmarks() throws -> [Bookmark] {
        let url = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Safari/Bookmarks.plist")
        guard let data = try? Data(contentsOf: url),
              let root = try? PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any] else {
            throw BridgeError.bookmarksUnreadable
        }
        var found: [Bookmark] = []
        func walk(_ node: [String: Any], folder: String) {
            let type = node["WebBookmarkType"] as? String
            if type == "WebBookmarkTypeLeaf",
               let string = node["URLString"] as? String, let url = URL(string: string), url.scheme?.hasPrefix("http") == true {
                let title = (node["URIDictionary"] as? [String: Any])?["title"] as? String ?? string
                found.append(Bookmark(title: title, url: url, folder: folder))
            }
            let title = node["Title"] as? String ?? ""
            // The Reading List is not bookmarks.
            guard title != "com.apple.ReadingList" else { return }
            let name = switch title {
            case "BookmarksBar": "Favorites"
            case "BookmarksMenu": "Bookmarks Menu"
            default: title
            }
            for child in node["Children"] as? [[String: Any]] ?? [] {
                walk(child, folder: name.isEmpty ? folder : name)
            }
        }
        walk(root, folder: "")
        return found
    }

    /// Imports a Bookmarks.html exported from Safari (or any browser).
    func importBookmarks(from file: URL) throws {
        let html = try String(contentsOf: file, encoding: .utf8)
        var found: [Bookmark] = []
        var folder = ""
        let pattern = /<H3[^>]*>(?<folder>[^<]*)<\/H3>|<A [^>]*HREF="(?<href>[^"]+)"[^>]*>(?<title>[^<]*)<\/A>/.ignoresCase()
        for match in html.matches(of: pattern) {
            if let name = match.output.folder {
                folder = String(name)
            } else if let href = match.output.href, let url = URL(string: String(href)), url.scheme?.hasPrefix("http") == true {
                found.append(Bookmark(title: String(match.output.title ?? href), url: url, folder: folder))
            }
        }
        bookmarks = found
        UserDefaults.standard.set(try? JSONEncoder().encode(found), forKey: "importedBookmarks")
    }

    /// Bookmarks grouped by folder, in file order.
    var folders: [(name: String, bookmarks: [Bookmark])] {
        var order: [String] = []
        var grouped: [String: [Bookmark]] = [:]
        for bookmark in bookmarks {
            if grouped[bookmark.folder] == nil { order.append(bookmark.folder) }
            grouped[bookmark.folder, default: []].append(bookmark)
        }
        return order.map { ($0.isEmpty ? "Bookmarks" : $0, grouped[$0] ?? []) }
    }
}
