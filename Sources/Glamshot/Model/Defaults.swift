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
    var customPresets: [SizePreset] { didSet { save(customPresets, "customPresets") } }
    var fileNameTemplate: String { didSet { store.set(fileNameTemplate, forKey: "fileNameTemplate") } }
    var format: ImageFormat { didSet { store.set(format.rawValue, forKey: "format") } }
    var jpegQuality: Double { didSet { store.set(jpegQuality, forKey: "jpegQuality") } }
    var saveFolder: URL? { didSet { store.set(saveFolder, forKey: "saveFolder") } }
    /// Seconds to wait after a page settles before photographing it, for animations and late content.
    var waitAfterLoading: Double { didSet { store.set(waitAfterLoading, forKey: "waitAfterLoading") } }

    private init() {
        capture = Self.load("capture", from: store) ?? CaptureOptions()
        look = Self.load("look", from: store) ?? .standard
        customPresets = Self.load("customPresets", from: store) ?? []
        fileNameTemplate = store.string(forKey: "fileNameTemplate") ?? FileNaming.defaultTemplate
        format = store.string(forKey: "format").flatMap(ImageFormat.init(rawValue:)) ?? .png
        jpegQuality = store.object(forKey: "jpegQuality") as? Double ?? 0.9
        saveFolder = store.url(forKey: "saveFolder")
        waitAfterLoading = store.object(forKey: "waitAfterLoading") as? Double ?? 0.5
    }

    var allPresets: [SizePreset] { SizePreset.builtIns + customPresets }

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
