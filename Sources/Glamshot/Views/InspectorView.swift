import AppKit
import DMKit
import GlamshotCore
import SwiftUI

/// Four cards in the order a shot is made: the output's size, how the page lays out in it, the
/// browser window, and what the window sits on. Every control has its title above it and fills
/// the card's width; switches sit at the right of their row.
struct InspectorView: View {
    @Bindable var model: ShootModel

    var body: some View {
        ScrollView {
            VStack(spacing: DMLayout.inspectorSpacing) {
                OutputCard(model: model)
                PageCard(model: model)
                WindowCard(model: model)
                BackdropCard(model: model)
            }
            .padding(DMLayout.inspectorPadding)
        }
    }
}

// MARK: - Output

private struct OutputCard: View {
    let model: ShootModel
    @State private var width = ""
    @State private var height = ""

    private var isDesktop: Bool { model.look.backdrop == .desktop }

    var body: some View {
        InspectorCard("Output", systemImage: "photo") {
            EmptyView()
        } content: {
            StackedControl("Size") {
                Menu {
                    ForEach(SizePreset.Group.allCases, id: \.self) { group in
                        let presets = Defaults.shared.allPresets.filter { $0.group == group }
                        if !presets.isEmpty {
                            Section(group.title) {
                                ForEach(presets) { preset in
                                    Toggle(preset.name, isOn: Binding(
                                        get: { model.currentPreset?.id == preset.id },
                                        set: { _ in model.choose(preset) }
                                    ))
                                }
                            }
                        }
                    }
                } label: {
                    Text(model.currentPreset?.name ?? "Custom")
                }
                .fixedSize()
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            HStack(spacing: 6) {
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

            StackedControl("Height") {
                FilledSegments("Height", selection: Binding(
                    get: { model.capture.fullPage && !isDesktop },
                    set: { value in model.setCapture(as: value ? "Turn On Full Page" : "Turn Off Full Page") { $0.fullPage = value } }
                ), segments: [
                    .init(value: false, title: "Screen", help: "The image is the output size"),
                    .init(value: true, title: "Full Page", help: "The image grows to the page’s full length")
                ])
            }
            .disabled(isDesktop)

            Text("Saves \(outputPixels)")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .onAppear(perform: syncFields)
        .onChange(of: model.capture) { syncFields() }
    }

    private var outputPixels: String {
        let fullPage = model.capture.fullPage && !isDesktop
        let height = fullPage ? model.fullPagePreview?.pointSize.height : nil
        let layout = FrameLayout.make(output: model.capture.outputSize, look: model.look, pageHeight: height)
        let scale = CGFloat(model.capture.scale)
        let width = Int(layout.canvasSize.width * scale)
        if fullPage, height == nil { return "\(width) px wide, full length" }
        return "\(width) × \(Int(layout.canvasSize.height * scale)) px"
    }

    private func syncFields() {
        width = "\(model.capture.width)"
        height = "\(model.capture.height)"
    }

    private func commit() {
        guard let w = Int(width), let h = Int(height), (200...8000).contains(w), (200...8000).contains(h) else {
            syncFields()
            return
        }
        model.setCapture(as: "Change Size") {
            $0.width = w
            $0.height = h
        }
    }
}

// MARK: - Page

private struct PageCard: View {
    let model: ShootModel

    var body: some View {
        InspectorCard("Page", systemImage: "doc.richtext") {
            EmptyView()
        } content: {
            InspectorSlider("Zoom", value: model.capture.zoom, in: CaptureOptions.zoomRange, default: 1, format: .percent) { value in
                model.beginGesture()
                model.capture.zoom = (value * 20).rounded() / 20
            } commit: {
                model.endGesture(as: "Change Zoom")
            }

            StackedControl("Appearance") {
                FilledSegments("Appearance", selection: Binding(
                    get: { model.capture.appearance },
                    set: { value in model.setCapture(as: "Change Page Appearance") { $0.appearance = value } }
                ), segments: CaptureOptions.Appearance.allCases.map { .init(value: $0, title: $0.title) })
            }

            Text("Lays out like a \(Int(model.layoutSize.width)) × \(Int(model.layoutSize.height)) browser window.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
                .fixedSize(horizontal: false, vertical: true)
        }
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
                StackedControl("Address") {
                    FilledSegments("Address", selection: Binding(
                        get: { model.look.safari.address },
                        set: { value in model.setLook(as: "Change Address") { $0.safari.address = value } }
                    ), segments: SafariOptions.Address.allCases.map { .init(value: $0, title: $0.title) })
                }
                SwitchRow("Tab Bar", isOn: Binding(
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
        InspectorSlider("Shadow", value: model.look.shadow, in: 0...1, default: 0.7, format: .percent) { value in
            model.beginGesture()
            model.look.shadow = value
        } commit: {
            model.endGesture(as: "Change Shadow")
        }
    }

    @ViewBuilder private var canvasControls: some View {
        SwitchRow("Auto Padding", isOn: Binding(
            get: { model.look.canvas.autoPadding },
            set: { value in model.setLook(as: value ? "Turn On Auto Padding" : "Turn Off Auto Padding") { $0.canvas.autoPadding = value } }
        ))
        .help("Picks the padding from the output size")
        if !model.look.canvas.autoPadding {
            InspectorSlider("Padding", value: model.look.canvas.padding, in: 0...400, default: 96,
                            format: .init(unit: .points), snapsToStep: true) { value in
                model.beginGesture()
                model.look.canvas.padding = value
            } commit: {
                model.endGesture(as: "Change Padding")
            }
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
        StackedControl("Window") {
            HStack {
                Button { model.centerDesktopWindow() } label: { Text("Center Window").frame(maxWidth: .infinity) }
                Button { model.fillDesktop() } label: { Text("Fill Desktop").frame(maxWidth: .infinity) }
            }
        }
        Text("Drag the window’s toolbar to move it, or its edges to resize it.")
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        StackedControl("Menu Bar") {
            FilledSegments("Menu Bar", selection: Binding(
                get: { model.look.desktop.menuBar },
                set: { value in model.setLook(as: "Change Menu Bar") { $0.desktop.menuBar = value } }
            ), segments: MenuBarAppearance.allCases.map { .init(value: $0, title: $0.title) })
        }
        LabeledTextField(title: "App Name", value: model.look.desktop.appName) { value in
            model.setLook(as: "Change App Name") { $0.desktop.appName = value }
        }
        LabeledTextField(title: "Clock", value: model.look.desktop.clock) { value in
            model.setLook(as: "Change Clock") { $0.desktop.clock = value }
        }
    }
}

/// Gradient swatches, then Shuffle, Image… and a color well, for the canvas or desktop.
private struct BackgroundPicker: View {
    let model: ShootModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 4)

    var body: some View {
        StackedControl("Background") {
            VStack(spacing: 8) {
                LazyVGrid(columns: columns, spacing: 6) {
                    ForEach(GradientLibrary.entries) { entry in
                        let selected = model.look.background.gradientName == entry.name
                        Button {
                            model.setLook(as: "Change Background") { $0.background = .gradient(name: entry.name, seed: 0) }
                        } label: {
                            BackgroundView(fill: .gradient(name: entry.name, seed: 0))
                                .frame(height: 30)
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
                HStack(spacing: 6) {
                    Button { model.shuffleBackground() } label: { Text("Shuffle").frame(maxWidth: .infinity) }
                        .disabled(model.look.background.gradientName == nil)
                    Button { Task { await model.chooseBackgroundImage() } } label: { Text("Image…").frame(maxWidth: .infinity) }
                    ColorPicker("Background Color", selection: Binding(
                        get: { model.look.background.color ?? .white },
                        set: { color in
                            model.setLook(as: "Change Background") { $0.background = .color(hex: NSColor(color).hexString) }
                        }
                    ))
                    .labelsHidden()
                    .help("Background Color")
                }
            }
        }
    }
}

/// A title at the left and a small switch at the right edge of the card.
private struct SwitchRow: View {
    let title: String
    @Binding var isOn: Bool

    init(_ title: String, isOn: Binding<Bool>) {
        self.title = title
        _isOn = isOn
    }

    var body: some View {
        Toggle(isOn: $isOn) {
            Text(title).frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.switch)
        .controlSize(.small)
    }
}

private struct LabeledTextField: View {
    let title: String
    let value: String
    let commit: (String) -> Void
    @State private var text = ""

    var body: some View {
        StackedControl(title) {
            TextField(title, text: $text)
                .textFieldStyle(.roundedBorder)
                .labelsHidden()
                .onSubmit { commit(text) }
        }
        .onAppear { text = value }
        .onChange(of: value) { text = value }
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
