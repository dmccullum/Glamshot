import AppKit
import DMKit
import GlamshotCore
import SwiftUI

/// Four cards, in the order a shot is made: the Look, the page's size, the browser window, and
/// what it sits on. Set-once options (wait time, file format, hidden elements, mobile sites) live
/// in Settings and the Page menu.
struct InspectorView: View {
    @Bindable var model: ShootModel

    var body: some View {
        ScrollView {
            VStack(spacing: DMLayout.inspectorSpacing) {
                LookCard(model: model)
                PageCard(model: model)
                WindowCard(model: model)
                BackdropCard(model: model)
            }
            .padding(DMLayout.inspectorPadding)
        }
    }
}

// MARK: - Look

private struct LookCard: View {
    let model: ShootModel

    var body: some View {
        InspectorCard("Look", systemImage: "sparkles") {
            Menu {
                ForEach(Defaults.shared.allLooks) { look in
                    Toggle(look.name, isOn: Binding(get: { model.currentLookID == look.id }, set: { _ in model.apply(look) }))
                }
                Divider()
                Button("Save Look…") { model.isNamingLook = true }
            } label: {
                Text(model.currentLookID.flatMap { id in Defaults.shared.allLooks.first { $0.id == id }?.name } ?? "Custom")
            }
            .frame(maxWidth: 170)
        }
    }
}

// MARK: - Page

private struct PageCard: View {
    let model: ShootModel
    @State private var width = ""
    @State private var height = ""

    private var isDesktop: Bool { model.look.backdrop == .desktop }

    var body: some View {
        InspectorCard("Page", systemImage: "rectangle.dashed") {
            // Separate identities, so switching backdrops never hands one pop-up's selection to the other.
            if isDesktop { displayPicker.id("display") } else { sizePicker.id("size") }
        } content: {
            HStack(spacing: 8) {
                TextField("Width", text: $width).onSubmit(commit)
                Text("×").foregroundStyle(.secondary)
                TextField("Height", text: $height).onSubmit(commit)
                Text("pt").foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()

            StackedControl("Scale") {
                FilledSegments("Scale", selection: Binding(
                    get: { model.capture.scale },
                    set: { value in model.setCapture(as: "Change Scale") { $0.scale = value } }
                ), segments: [1, 2, 3].map { .init(value: $0, title: "\($0)×") })
            }

            StackedControl("Appearance") {
                FilledSegments("Appearance", selection: Binding(
                    get: { model.capture.appearance },
                    set: { value in model.setCapture(as: "Change Page Appearance") { $0.appearance = value } }
                ), segments: CaptureOptions.Appearance.allCases.map { .init(value: $0, title: $0.title) })
            }

            if isDesktop {
                Text("Drag the window’s toolbar to move it, or its edges to resize it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            } else {
                Toggle("Full Page", isOn: Binding(
                    get: { model.capture.fullPage },
                    set: { value in model.setCapture(as: value ? "Turn On Full Page" : "Turn Off Full Page") { $0.fullPage = value } }
                ))
            }

            Text("Saves \(outputSize)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .onAppear(perform: syncFields)
        .onChange(of: model.capture) { syncFields() }
    }

    private var sizePicker: some View {
        Picker("Size", selection: Binding(
            get: { model.currentPreset?.id ?? "" },
            set: { id in
                if let preset = Defaults.shared.allPresets.first(where: { $0.id == id }) { model.choose(preset) }
            }
        )) {
            if model.currentPreset == nil { Text("Custom").tag("") }
            ForEach(SizePreset.Group.allCases, id: \.self) { group in
                let presets = Defaults.shared.allPresets.filter { $0.group == group }
                if !presets.isEmpty {
                    Section(group.title) {
                        ForEach(presets) { Text($0.name).tag($0.id) }
                    }
                }
            }
        }
        .labelsHidden()
        .frame(maxWidth: 170)
    }

    private var displayPicker: some View {
        Picker("Display", selection: Binding(
            get: { model.look.desktop.displayID },
            set: { value in model.setLook(as: "Change Display") { $0.desktop.displayID = value } }
        )) {
            ForEach(SizePreset.builtIns.filter { $0.group == .mac }) { Text($0.name).tag($0.id) }
        }
        .labelsHidden()
        .frame(maxWidth: 170)
    }

    private var outputSize: String {
        let page = model.capture.fullPage && !isDesktop
            ? model.fullPagePreview?.pointSize ?? model.capture.viewport
            : model.capture.viewport
        let layout = FrameLayout.make(page: page, look: model.look)
        let scale = CGFloat(model.capture.scale)
        return "\(Int(layout.canvasSize.width * scale)) × \(Int(layout.canvasSize.height * scale)) px"
    }

    private func syncFields() {
        width = "\(model.capture.width)"
        height = "\(model.capture.height)"
    }

    private func commit() {
        guard let w = Int(width), let h = Int(height), (100...8000).contains(w), (100...8000).contains(h) else {
            syncFields()
            return
        }
        if isDesktop {
            // On a desktop the fields size the window's page area.
            model.setDesktopWindow(size: CGSize(width: CGFloat(w), height: CGFloat(h) + chromeHeight), as: "Resize Window")
        } else {
            model.setCapture(as: "Change Size") {
                $0.width = w
                $0.height = h
            }
        }
    }

    private var chromeHeight: CGFloat {
        model.look.window == .safari ? ChromeMetrics.chromeHeight(showsTabBar: model.look.safari.showsTabBar) : 0
    }
}

// MARK: - Window

private struct WindowCard: View {
    let model: ShootModel

    private var isOn: Bool { model.look.window == .safari }

    var body: some View {
        InspectorCard("Safari Window", systemImage: "macwindow", isActive: isOn) {
            Toggle("Safari Window", isOn: Binding(
                get: { isOn },
                set: { value in
                    model.setLook(as: value ? "Show Safari Window" : "Hide Safari Window") { $0.window = value ? .safari : .none }
                }
            ))
            .toggleStyle(.switch)
            .labelsHidden()
            .controlSize(.small)
        } content: {
            if isOn {
                StackedControl("Toolbar") {
                    FilledSegments("Toolbar", selection: Binding(
                        get: { model.look.safari.appearance },
                        set: { value in model.setLook(as: "Change Toolbar Appearance") { $0.safari.appearance = value } }
                    ), segments: SafariOptions.Appearance.allCases.map { .init(value: $0, title: $0.title) })
                }
                Picker("Address", selection: Binding(
                    get: { model.look.safari.address },
                    set: { value in model.setLook(as: "Change Address") { $0.safari.address = value } }
                )) {
                    ForEach(SafariOptions.Address.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                Toggle("Tab Bar", isOn: Binding(
                    get: { model.look.safari.showsTabBar },
                    set: { value in model.setLook(as: value ? "Show Tab Bar" : "Hide Tab Bar") { $0.safari.showsTabBar = value } }
                ))
            }
        }
    }
}

// MARK: - Backdrop

private struct BackdropCard: View {
    let model: ShootModel

    var body: some View {
        InspectorCard("Backdrop", systemImage: "photo.on.rectangle") {
            EmptyView()
        } content: {
            FilledSegments("Backdrop", selection: Binding(
                get: { model.look.backdrop },
                set: { value in model.setLook(as: "Change Backdrop") { $0.backdrop = value } }
            ), segments: Backdrop.allCases.map { .init(value: $0, title: $0.title) })

            switch model.look.backdrop {
            case .none:
                shadowSlider
            case .canvas:
                BackgroundPicker(model: model)
                canvasControls
                shadowSlider
            case .desktop:
                BackgroundPicker(model: model)
                desktopControls
            }
        }
    }

    private var shadowSlider: some View {
        InspectorSlider("Shadow", value: model.look.shadow, in: 0...1, default: 0.7) { value in
            model.beginGesture()
            model.look.shadow = value
        } commit: {
            model.endGesture(as: "Change Shadow")
        }
    }

    @ViewBuilder private var canvasControls: some View {
        Picker("Aspect Ratio", selection: Binding(
            get: { model.look.canvas.aspect },
            set: { value in model.setLook(as: "Change Aspect Ratio") { $0.canvas.aspect = value } }
        )) {
            ForEach(AspectRatio.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        Toggle("Auto Balance", isOn: Binding(
            get: { model.look.canvas.autoBalance },
            set: { value in model.setLook(as: value ? "Turn On Auto Balance" : "Turn Off Auto Balance") { $0.canvas.autoBalance = value } }
        ))
        .help("Picks padding and placement for the window’s shape")
        if !model.look.canvas.autoBalance {
            InspectorSlider("Padding", value: model.look.canvas.padding, in: 0...400, default: 96,
                            format: .init(unit: .points), snapsToStep: true) { value in
                model.beginGesture()
                model.look.canvas.padding = value
            } commit: {
                model.endGesture(as: "Change Padding")
            }
            AlignmentGrid(selection: Binding(
                get: { model.look.canvas.alignment },
                set: { value in model.setLook(as: "Change Alignment") { $0.canvas.alignment = value } }
            ))
        }
        if model.look.window == .none {
            InspectorSlider("Corner Radius", value: model.look.canvas.cornerRadius, in: 0...40, default: 14,
                            format: .init(unit: .points), snapsToStep: true) { value in
                model.beginGesture()
                model.look.canvas.cornerRadius = value
            } commit: {
                model.endGesture(as: "Change Corner Radius")
            }
        }
    }

    @ViewBuilder private var desktopControls: some View {
        HStack {
            Button("Center Window") { model.centerDesktopWindow() }
            Button("Fill Desktop") { model.fillDesktop() }
        }
        Picker("Menu Bar Text", selection: Binding(
            get: { model.look.desktop.menuBar },
            set: { value in model.setLook(as: "Change Menu Bar Text") { $0.desktop.menuBar = value } }
        )) {
            ForEach(MenuBarAppearance.allCases, id: \.self) { Text($0.title).tag($0) }
        }
        LabeledTextField(title: "App Name", value: model.look.desktop.appName) { value in
            model.setLook(as: "Change App Name") { $0.desktop.appName = value }
        }
        LabeledTextField(title: "Clock", value: model.look.desktop.clock) { value in
            model.setLook(as: "Change Clock") { $0.desktop.clock = value }
        }
    }
}

/// Gradient swatches, then Shuffle, Color and Image… for the canvas or desktop.
private struct BackgroundPicker: View {
    let model: ShootModel

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 6)]

    var body: some View {
        LazyVGrid(columns: columns, spacing: 6) {
            ForEach(GradientLibrary.entries) { entry in
                let selected = model.look.background.gradientName == entry.name
                Button {
                    model.setLook(as: "Change Background") { $0.background = .gradient(name: entry.name, seed: 0) }
                } label: {
                    BackgroundView(fill: .gradient(name: entry.name, seed: 0))
                        .frame(height: 32)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay {
                            RoundedRectangle(cornerRadius: 6, style: .continuous)
                                .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1)
                        }
                }
                .buttonStyle(.plain)
                .help(entry.name)
                .accessibilityLabel(entry.name)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
        HStack {
            Button("Shuffle") { model.shuffleBackground() }
                .disabled(model.look.background.gradientName == nil)
            ColorPicker("Color", selection: Binding(
                get: { model.look.background.color ?? .white },
                set: { color in
                    model.setLook(as: "Change Background") { $0.background = .color(hex: NSColor(color).hexString) }
                }
            ))
            .labelsHidden()
            .help("Background Color")
            Button("Image…") { Task { await model.chooseBackgroundImage() } }
        }
    }
}

private struct LabeledTextField: View {
    let title: String
    let value: String
    let commit: (String) -> Void
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .onSubmit { commit(text) }
        }
        .onAppear { text = value }
        .onChange(of: value) { text = value }
    }
}

/// Nine buttons for where the window sits on the canvas.
private struct AlignmentGrid: View {
    @Binding var selection: CanvasAlignment

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Alignment")
            Grid(horizontalSpacing: 4, verticalSpacing: 4) {
                ForEach(0..<3) { row in
                    GridRow {
                        ForEach(0..<3) { column in
                            let value = CanvasAlignment.allCases[row * 3 + column]
                            Button {
                                selection = value
                            } label: {
                                RoundedRectangle(cornerRadius: 3)
                                    .fill(selection == value ? Color.accentColor : Color.secondary.opacity(0.25))
                                    .frame(width: 22, height: 14)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(String(describing: value))
                            .accessibilityAddTraits(selection == value ? .isSelected : [])
                        }
                    }
                }
            }
        }
    }
}

extension BackgroundFill {
    var gradientName: String? {
        if case .gradient(let name, _) = self { return name }
        return nil
    }

    var color: Color? {
        if case .color(let hex) = self { return Color(hex: hex) }
        return nil
    }
}
