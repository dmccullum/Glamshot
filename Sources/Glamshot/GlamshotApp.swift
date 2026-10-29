import AppKit
import DMKit
import SwiftUI

@main
struct GlamshotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        WindowGroup(id: "shoot") {
            ContentView()
        }
        .defaultSize(width: 1280, height: 820)
        .windowToolbarStyle(.unified)
        .commands {
            AboutCommands()
            UndoCommands()
            GlamshotCommands()
            FamilyHelpCommands(
                help: URL(string: "https://github.com/dmccullum/Glamshot#readme")!,
                releaseNotes: URL(string: "https://github.com/dmccullum/Glamshot/releases"),
                reportIssue: URL(string: "https://github.com/dmccullum/Glamshot/issues/new")
            )
        }

        Settings {
            SettingsView()
        }

        AboutScene(links: AboutLinks(sourceCode: URL(string: "https://github.com/dmccullum/Glamshot")),
                   showsIcon: false) {
            FlashSignature()
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        let arguments = ProcessInfo.processInfo.arguments
        if let index = arguments.firstIndex(of: "--self-test") {
            let folder = arguments.indices.contains(index + 1) ? arguments[index + 1] : "Tests/Fixtures"
            Task { await SelfTest.run(fixtures: URL(fileURLWithPath: folder)) }
        }
        if let index = arguments.firstIndex(of: "--capture") {
            Task { await CommandLineCapture.run(Array(arguments[(index + 1)...])) }
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationDockMenu(_ sender: NSApplication) -> NSMenu? {
        let menu = NSMenu()
        menu.addItem(withTitle: "New Window", action: #selector(newWindow), keyEquivalent: "").target = self
        return menu
    }

    @objc private func newWindow() {
        NSApp.sendAction(Selector(("newWindowForTab:")), to: nil, from: nil)
        if NSApp.windows.filter(\.isVisible).isEmpty {
            NSApp.activate()
        }
    }
}
