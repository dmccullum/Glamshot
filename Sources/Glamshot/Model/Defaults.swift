import Foundation
import GlamshotCore
import Observation
import UniformTypeIdentifiers

/// App-wide settings and the person's own sizes and Looks, kept in UserDefaults.
@Observable
final class Defaults {
    static let shared = Defaults()

    @ObservationIgnored private let store = UserDefaults.standard

    var capture: CaptureOptions { didSet { save(capture, "capture") } }
    var look: Look { didSet { save(look, "look") } }
    /// Every size in the Size menu, built-in and the person's own, in order. Any of them can be
    /// edited or deleted; Restore Built-In Sizes brings the built-ins back.
    var presets: [SizePreset] { didSet { save(presets, "presets") } }
    var fileNameTemplate: String { didSet { store.set(fileNameTemplate, forKey: "fileNameTemplate") } }
    var format: ImageFormat { didSet { store.set(format.rawValue, forKey: "format") } }
    var jpegQuality: Double { didSet { store.set(jpegQuality, forKey: "jpegQuality") } }
    var saveFolder: URL? { didSet { store.set(saveFolder, forKey: "saveFolder") } }
    /// The last size typed that isn't a preset, for Size › Custom.
    var customSize: CGSize { didSet { store.set([customSize.width, customSize.height], forKey: "customSize") } }
    /// Seconds to wait after a page settles before photographing it, for animations and late content.
    var waitAfterLoading: Double { didSet { store.set(waitAfterLoading, forKey: "waitAfterLoading") } }

    private init() {
        capture = Self.load("capture", from: store) ?? CaptureOptions()
        look = Self.load("look", from: store) ?? .standard
        // Sizes saved before built-ins were editable were only the person's own.
        presets = Self.load("presets", from: store) ?? SizePreset.builtIns + (Self.load("customPresets", from: store) ?? [])
        fileNameTemplate = store.string(forKey: "fileNameTemplate") ?? FileNaming.defaultTemplate
        format = store.string(forKey: "format").flatMap(ImageFormat.init(rawValue:)) ?? .png
        jpegQuality = store.object(forKey: "jpegQuality") as? Double ?? 0.9
        saveFolder = store.url(forKey: "saveFolder")
        waitAfterLoading = store.object(forKey: "waitAfterLoading") as? Double ?? 0.5
        let custom = store.array(forKey: "customSize") as? [Double] ?? [1440, 900]
        customSize = CGSize(width: custom.first ?? 1440, height: custom.last ?? 900)
    }

    /// Whether a built-in size is missing or edited.
    var builtInsChanged: Bool {
        SizePreset.builtIns.contains { builtIn in presets.first { $0.id == builtIn.id } != builtIn }
    }

    /// Puts every built-in size back as shipped, each group in its usual order, keeping the
    /// person's own sizes after the built-ins in their group.
    func restoreBuiltInSizes() {
        let builtInIDs = Set(SizePreset.builtIns.map(\.id))
        let own = presets.filter { !builtInIDs.contains($0.id) }
        presets = SizePreset.Group.allCases.flatMap { group in
            SizePreset.builtIns.filter { $0.group == group } + own.filter { $0.group == group }
        }
    }

    private func save<T: Encodable>(_ value: T, _ key: String) {
        store.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<T: Decodable>(_ key: String, from store: UserDefaults) -> T? {
        store.data(forKey: key).flatMap { try? JSONDecoder().decode(T.self, from: $0) }
    }
}

enum ImageFormat: String, CaseIterable, Identifiable {
    case png, jpeg, heic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .png: "PNG"
        case .jpeg: "JPEG"
        case .heic: "HEIC"
        }
    }

    var contentType: UTType {
        switch self {
        case .png: .png
        case .jpeg: .jpeg
        case .heic: .heic
        }
    }

    var fileExtension: String { contentType.preferredFilenameExtension ?? rawValue }

    /// JPEG has no transparency.
    var supportsTransparency: Bool { self != .jpeg }
}

/// Pages opened recently, for File › Open Recent.
@Observable
final class RecentPages {
    static let shared = RecentPages()
    private(set) var urls: [URL]

    private init() {
        urls = (UserDefaults.standard.stringArray(forKey: "recentPages") ?? []).compactMap(URL.init(string:))
    }

    func add(_ url: URL) {
        urls.removeAll { $0 == url }
        urls.insert(url, at: 0)
        urls = Array(urls.prefix(12))
        UserDefaults.standard.set(urls.map(\.absoluteString), forKey: "recentPages")
    }

    func clear() {
        urls = []
        UserDefaults.standard.removeObject(forKey: "recentPages")
    }
}
