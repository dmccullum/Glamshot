import AppKit
import DMKit
import GlamshotCore
import SwiftUI

struct ContentView: View {
    @State private var model = ShootModel()
    @State private var showsInspector = true
    @SceneStorage("showsShotsTray") private var showsShotsTray = true
    @SceneStorage("address") private var savedAddress = ""
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        NavigationSplitView {
            SidebarView(model: model)
                .navigationSplitViewColumnWidth(min: 200, ideal: 230, max: 320)
        } detail: {
            VStack(spacing: 0) {
                CanvasView(model: model)
                if showsShotsTray, !model.shots.isEmpty {
                    Divider()
                    ShotsTray(model: model)
                }
            }
            .statusCapsule($model.status)
        }
        .inspector(isPresented: $showsInspector) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
        }
        .toolbar { ShootToolbar(model: model, showsInspector: $showsInspector) }
        .navigationTitle(model.url.flatMap(FileNaming.domain(of:)) ?? "Glamshot")
        .navigationSubtitle(subtitle)
        .focusedSceneValue(\.shoot, model)
        .focusedSceneValue(\.inspectorShown, $showsInspector)
        .focusedSceneValue(\.shotsTrayShown, $showsShotsTray)
        .background(WindowReader { window in model.window = window })
        .onAppear {
            model.undoManager = undoManager
            if model.url == nil, let url = URL(string: savedAddress), !savedAddress.isEmpty { model.load(url) }
        }
        .onChange(of: undoManager) { model.undoManager = undoManager }
        .onChange(of: model.url) { savedAddress = model.url?.absoluteString ?? "" }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .frame(minWidth: 900, minHeight: 560)
    }

    private var subtitle: String {
        "\(model.capture.width)×\(model.capture.height) · \(model.capture.scale)× · \(model.look.summary)"
    }
}

/// Finds the hosting window.
struct WindowReader: NSViewRepresentable {
    let found: (NSWindow?) -> Void

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async { found(view.window) }
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async { found(view.window) }
    }
}

struct ShootToolbar: ToolbarContent {
    @Bindable var model: ShootModel
    @Binding var showsInspector: Bool
    @FocusState private var addressFocused: Bool

    var body: some ToolbarContent {
        ToolbarItemGroup(placement: .navigation) {
            Button { model.goBack() } label: { Label("Back", systemImage: "chevron.left") }
                .help("Back (⌘[)")
                .disabled(!model.canGoBack)
            Button { model.goForward() } label: { Label("Forward", systemImage: "chevron.right") }
                .help("Forward (⌘])")
                .disabled(!model.canGoForward)
        }
        ToolbarItem(placement: .principal) {
            HStack(spacing: 6) {
                TextField("Search or enter website name", text: $model.addressText)
                    .textFieldStyle(.plain)
                    .focused($addressFocused)
                    .onSubmit { model.load(model.addressText) }
                    .onChange(of: model.addressFocusRequest) { addressFocused = true }
                if model.isLoading {
                    Button { model.stop() } label: { Label("Stop", systemImage: "xmark") }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Stop Loading (⌘.)")
                } else {
                    Button { model.reload() } label: { Label("Reload", systemImage: "arrow.clockwise") }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Reload Page (⌘R)")
                        .disabled(!model.hasPage)
                }
            }
            .padding(.horizontal, 12)
            .frame(minWidth: 320, idealWidth: 460, maxWidth: 560)
        }
        ToolbarItem(placement: .status) {
            if let activity = model.activity {
                HStack(spacing: 8) {
                    if let progress = activity.progress {
                        ProgressView(value: progress).frame(width: 80)
                    } else {
                        ProgressView().controlSize(.small)
                    }
                    Text(activity.title).font(.callout).foregroundStyle(.secondary)
                    if model.canCancel {
                        Button("Cancel") { model.cancel() }.controlSize(.small)
                    }
                }
            }
        }
        ToolbarItemGroup(placement: .primaryAction) {
            Menu {
                ForEach(Array(Defaults.shared.allLooks.enumerated()), id: \.element.id) { _, look in
                    Button(look.name) { model.apply(look) }
                }
            } label: {
                Label("Look", systemImage: "sparkles")
            }
            .help("Choose a Look")
            Button { Task { await model.copyImage() } } label: { Label("Copy Image", systemImage: "doc.on.doc") }
                .help("Copy Image (⌘C)")
                .disabled(!model.hasPage)
            Button { Task { await model.saveImage() } } label: { Label("Save Image", systemImage: "square.and.arrow.down") }
                .help("Save Image… (⌘S)")
                .disabled(!model.hasPage)
            Button { showsInspector.toggle() } label: { Label("Inspector", systemImage: "sidebar.right") }
                .help(showsInspector ? "Hide Inspector (⌥⌘I)" : "Show Inspector (⌥⌘I)")
        }
    }
}
