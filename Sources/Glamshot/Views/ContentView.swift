import AppKit
import DMKit
import GlamshotCore
import SwiftUI

struct ContentView: View {
    @State private var model = ShootModel()
    @State private var showsInspector = true
    @SceneStorage("address") private var savedAddress = ""
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(spacing: 0) {
            CanvasView(model: model)

        }
        .statusCapsule($model.status)
        .inspector(isPresented: $showsInspector) {
            InspectorView(model: model)
                .inspectorColumnWidth(min: 260, ideal: 290, max: 360)
        }
        .toolbar { ShootToolbar(model: model, showsInspector: $showsInspector) }
        // The title names the window in the Window menu and Mission Control; the toolbar leaves it
        // out, since the address field already shows the page and the inspector the size.
        .navigationTitle(model.url.flatMap(FileNaming.domain(of:)) ?? "Glamshot")
        .toolbar(removing: .title)
        .focusedSceneValue(\.shoot, model)
        .focusedSceneValue(\.inspectorShown, $showsInspector)
        .background(WindowReader { window in model.window = window })
        .onAppear {
            model.undoManager = undoManager
            PendingOpen.shared.register(model)
            if model.url == nil, PendingOpen.shared.urls.isEmpty, let url = URL(string: savedAddress), !savedAddress.isEmpty { model.load(url) }
        }
        .onChange(of: undoManager) { model.undoManager = undoManager }
        .onChange(of: PendingOpen.shared.urls, initial: true) {
            guard PendingOpen.shared.frontmost === model || model.window == nil,
                  let url = PendingOpen.shared.take() else { return }
            model.load(url)
        }
        .onDisappear { PendingOpen.shared.unregister(model) }
        // Files opened from Finder go to an open window; SwiftUI makes one only when none is open.
        .handlesExternalEvents(preferring: ["*"], allowing: ["*"])
        .onOpenURL { url in model.load(CanvasView.resolved(url)) }
        .onChange(of: model.url) { savedAddress = model.url?.absoluteString ?? "" }
        .sheet(isPresented: $model.isChoosingExportSizes) {
            ExportSizesSheet(model: model)
        }
        .sheet(isPresented: $model.isEditingHiddenElements) {
            HideElementsSheet(model: model)
        }
        .alert(item: $model.alert) { alert in
            Alert(title: Text(alert.title), message: Text(alert.message))
        }
        .frame(minWidth: 760, minHeight: 520)
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
            .frame(minWidth: 360, idealWidth: 720, maxWidth: .infinity)
        }
        // One screen or the whole page decides most of the rest, so it sits at the top right, as
        // Granular's mode does. It shows for every frame; Full Page moves Safari to Page and Desktop
        // to Canvas.
        ToolbarItem(placement: .primaryAction) {
            Picker("Capture", selection: Binding(get: { model.capture.fullPage }, set: { model.setFullPage($0) })) {
                Text("Screen").tag(false).help("One screen at the output size (⌘1)")
                Text("Full Page").tag(true).help("The page’s whole length (⌘2)")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Photograph one screen or the full page (⌘1, ⌘2)")
        }
        // Save, copy, export and share, to the right of the mode, as in Granular.
        ToolbarItem(placement: .primaryAction) {
            ShareButton(model: model)
        }
    }
}

/// Opens the share picker under itself: Save Image…, Copy Image and Export Sizes…, then sharing.
struct ShareButton: View {
    let model: ShootModel
    @State private var anchor = ShareAnchor()

    var body: some View {
        Button {
            model.share(from: anchor.view)
        } label: {
            Label("Share", systemImage: "square.and.arrow.up")
                .labelStyle(.iconOnly)
        }
        .background { ShareAnchorView(anchor: anchor) }
        .disabled(!model.hasPage)
        .help("Save, copy, export or share the image")
        .accessibilityLabel("Share or Save")
    }
}

/// The view the share picker points at.
final class ShareAnchor {
    weak var view: NSView?
}

private struct ShareAnchorView: NSViewRepresentable {
    let anchor: ShareAnchor

    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        anchor.view = view
        return view
    }

    func updateNSView(_ view: NSView, context: Context) {
        anchor.view = view
    }
}
