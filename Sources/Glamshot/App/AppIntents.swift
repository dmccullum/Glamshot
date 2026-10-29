import AppIntents
import AppKit
import GlamshotCore
import UniformTypeIdentifiers

// Shortcuts actions. They run inside Glamshot, in a window of their own that never shows, so
// they share the person's sign-ins, sizes, Looks and output format with the app.

/// A size as Shortcuts sees it: every built-in and custom size, by name.
struct SizeEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Glamshot Size"
    static let defaultQuery = SizeQuery()

    let id: String
    let name: String
    let dimensions: String

    init(_ preset: SizePreset) {
        id = preset.id
        name = preset.name
        dimensions = "\(preset.dimensions) · \(preset.scale)×"
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(dimensions)")
    }
}

struct SizeQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [SizeEntity.ID]) async throws -> [SizeEntity] {
        Defaults.shared.allPresets.filter { identifiers.contains($0.id) }.map(SizeEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [SizeEntity] {
        Defaults.shared.allPresets.filter { $0.name.localizedStandardContains(string) }.map(SizeEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [SizeEntity] {
        Defaults.shared.allPresets.map(SizeEntity.init)
    }
}

/// A Look as Shortcuts sees it.
struct LookEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Glamshot Preset"
    static let defaultQuery = LookQuery()

    let id: String
    let name: String
    let summary: String

    init(_ look: Look) {
        id = look.id
        name = look.name
        summary = look.summary
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "\(name)", subtitle: "\(summary)")
    }
}

struct LookQuery: EntityStringQuery {
    @MainActor
    func entities(for identifiers: [LookEntity.ID]) async throws -> [LookEntity] {
        Defaults.shared.allLooks.filter { identifiers.contains($0.id) }.map(LookEntity.init)
    }

    @MainActor
    func entities(matching string: String) async throws -> [LookEntity] {
        Defaults.shared.allLooks.filter { $0.name.localizedStandardContains(string) }.map(LookEntity.init)
    }

    @MainActor
    func suggestedEntities() async throws -> [LookEntity] {
        Defaults.shared.allLooks.map(LookEntity.init)
    }
}

struct TakeGlamshotIntent: AppIntent {
    static let title: LocalizedStringResource = "Take Glamshot"
    static let description = IntentDescription(
        "Photographs a webpage at a size and frames it with a preset, as an image in Glamshot’s output format.",
        categoryName: "Webpages"
    )

    @Parameter(title: "Web Address", inputConnectionBehavior: .connectToPreviousIntentResult)
    var url: URL

    @Parameter(title: "Size", description: "Leave empty for MacBook Pro 14\".")
    var size: SizeEntity?

    @Parameter(title: "Preset", description: "Leave empty for the preset last used in Glamshot.")
    var look: LookEntity?

    @Parameter(title: "Full Page", default: false)
    var fullPage: Bool

    static var parameterSummary: some ParameterSummary {
        Summary("Take Glamshot of \(\.$url) at \(\.$size) with \(\.$look)") {
            \.$fullPage
        }
    }

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<IntentFile> {
        let defaults = Defaults.shared
        let preset = size.flatMap { entity in defaults.allPresets.first { $0.id == entity.id } } ?? .macBookPro14
        let chosenLook = look.flatMap { entity in defaults.allLooks.first { $0.id == entity.id } } ?? defaults.look
        var options = defaults.capture
        options.apply(preset)
        options.fullPage = fullPage

        let shoot = try await HeadlessShoot(url: url, viewport: FrameLayout.pageSize(output: options.outputSize, look: chosenLook.resolved(for: options.outputSize, fullPage: options.fullPage), fullPage: options.fullPage))
        defer { shoot.close() }
        let shot = try await shoot.model.render(look: chosenLook, capture: options)

        let format = defaults.format
        let name = shoot.model.fileName(for: chosenLook, sizeName: preset.name, capture: options) + "." + format.fileExtension
        guard let data = shot.data(format: format) else { throw CaptureError.snapshotFailed }
        return .result(value: IntentFile(data: data, filename: name, type: format.contentType))
    }
}

/// A shoot in a window that stays off screen, for Shortcuts.
@MainActor
final class HeadlessShoot {
    let model = ShootModel(rememberingSettings: false)
    private let window: NSWindow

    init(url: URL, viewport: CGSize) async throws {
        window = NSWindow(contentRect: CGRect(origin: .zero, size: viewport), styleMask: [.borderless],
                          backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.alphaValue = 0.01
        window.ignoresMouseEvents = true
        let container = NSView(frame: CGRect(origin: .zero, size: viewport))
        container.addSubview(model.webView)
        window.contentView = container
        window.orderFrontRegardless()
        model.webView.setFrameSize(viewport)
        model.load(url)

        let start = Date.now
        repeat {
            try await Task.sleep(for: .milliseconds(100))
            if let alert = model.alert { throw ShortcutError.couldNotLoad(alert.message) }
        } while (model.isLoading || model.url == nil) && Date.now.timeIntervalSince(start) < 30
        guard model.hasPage else { throw ShortcutError.couldNotLoad("The page didn’t load within 30 seconds.") }
    }

    func close() {
        window.close()
    }
}

enum ShortcutError: LocalizedError {
    case couldNotLoad(String)

    var errorDescription: String? {
        switch self {
        case .couldNotLoad(let reason): "Glamshot couldn’t load the page. \(reason)"
        }
    }
}

/// Lists the action in Spotlight and the Shortcuts app as soon as Glamshot is installed.
struct GlamshotShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: TakeGlamshotIntent(),
            phrases: [
                "Take a \(.applicationName)",
                "Photograph a webpage with \(.applicationName)"
            ],
            shortTitle: "Take Glamshot",
            systemImageName: "camera"
        )
    }
}
