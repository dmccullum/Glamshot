import AppKit
import DMKit
import GlamshotCore
import SwiftUI

struct InspectorView: View {
    @Bindable var model: ShootModel

    var body: some View {
        ScrollView {
            VStack(spacing: DMLayout.inspectorSpacing) {
                SizeCard(model: model)
                PageCard(model: model)
                LookCard(model: model)
                WindowCard(model: model)
                BackdropCard(model: model)
                BackgroundCard(model: model)
                OutputCard()
            }
            .padding(DMLayout.inspectorPadding)
        }
    }
}

// MARK: - Size

private struct SizeCard: View {
    let model: ShootModel
    @State private var width = ""
    @State private var height = ""

    private var isDesktop: Bool { model.look.backdrop == .desktop }

    var body: some View {
        InspectorCard("Size", systemImage: "rectangle.dashed") {
            EmptyView()
        } content: {
            HStack(spacing: 8) {
                TextField("Width", text: $width).onSubmit(commit)
                Text("×").foregroundStyle(.secondary)
                TextField("Height", text: $height).onSubmit(commit)
                Text("pt").foregroundStyle(.secondary)
            }
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
            .disabled(isDesktop)
            .help(isDesktop ? "On a desktop, the window’s size sets the viewport" : "The viewport in points")

            StackedControl("Scale") {
                FilledSegments("Scale", selection: Binding(
                    get: { model.capture.scale },
                    set: { value in model.setCapture(as: "Change Scale") { $0.scale = value } }
                ), segments: [1, 2, 3].map { .init(value: $0, title: "\($0)×") })
            }

            Toggle("Full Page", isOn: Binding(
                get: { model.capture.fullPage },
                set: { value in model.setCapture(as: value ? "Turn On Full Page" : "Turn Off Full Page") { $0.fullPage = value } }
            ))
            .disabled(isDesktop)

            Text(outputDescription)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        }
        .onAppear(perform: syncFields)
        .onChange(of: model.capture) { syncFields() }
    }

    private var outputDescription: String {
        let page = model.capture.fullPage ? model.fullPagePreview?.pointSize ?? model.capture.viewport : model.capture.viewport
        let layout = FrameLayout.make(page: page, look: model.look)
        let scale = CGFloat(model.capture.scale)
        return "Image: \(Int(layout.canvasSize.width * scale)) × \(Int(layout.canvasSize.height * scale)) px"
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
        model.setCapture(as: "Change Size") {
            $0.width = w
            $0.height = h
        }
    }
}

// MARK: - Page

private struct PageCard: View {
    let model: ShootModel
    @State private var selectors = ""

    var body: some View {
        InspectorCard("Page", systemImage: "doc.richtext") {
            EmptyView()
        } content: {
            StackedControl("Appearance") {
                FilledSegments("Appearance", selection: Binding(
                    get: { model.capture.appearance },
                    set: { value in model.setCapture(as: "Change Page Appearance") { $0.appearance = value } }
                ), segments: CaptureOptions.Appearance.allCases.map { .init(value: $0, title: $0.title) })
            }
            StackedControl("Site Layout") {
                FilledSegments("Site Layout", selection: Binding(
                    get: { model.capture.userAgent },
                    set: { value in model.setCapture(as: "Change Site Layout") { $0.userAgent = value } }
                ), segments: [.init(value: UserAgent.mac, title: "Desktop"), .init(value: UserAgent.iPhone, title: "Phone")])
            }
            InspectorSlider("Delay", value: model.capture.delay, in: 0...5, default: 0.5,
                            format: .init(fractionDigits: 1, unit: .init(symbol: "s", spokenName: "seconds"), step: 0.1), snapsToStep: true) { value in
                model.beginGesture()
                model.capture.delay = value
            } commit: {
                model.endGesture(as: "Change Delay")
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("Hide Elements")
                TextField("CSS selectors, such as #cookie-banner", text: $selectors, axis: .vertical)
                    .lineLimit(2...4)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { model.setCapture(as: "Hide Elements") { $0.hiddenSelectors = selectors } }
            }
        }
        .onAppear { selectors = model.capture.hiddenSelectors }
        .onChange(of: model.capture.hiddenSelectors) { selectors = model.capture.hiddenSelectors }
    }
}

// MARK: - Look

private struct LookCard: View {
    let model: ShootModel
    @State private var isNaming = false
    @State private var name = ""

    var body: some View {
        InspectorCard("Look", systemImage: "sparkles") {
            EmptyView()
        } content: {
            Picker("Look", selection: Binding(
                get: { model.currentLookID ?? "" },
                set: { id in if let look = Defaults.shared.allLooks.first(where: { $0.id == id }) { model.apply(look) } }
            )) {
                if model.currentLookID == nil { Text("Custom").tag("") }
                ForEach(Defaults.shared.allLooks) { Text($0.name).tag($0.id) }
            }
            .labelsHidden()
            Button("Save Look…") {
                name = ""
                isNaming = true
            }
        }
        .alert("Save Look", isPresented: $isNaming) {
            TextField("Name", text: $name)
            Button("Save") { saveLook() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The window, backdrop and background are saved under this name.")
        }
    }

    private func saveLook() {
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }
        var look = model.look
        look.id = UUID().uuidString
        look.name = trimmed
        Defaults.shared.customLooks.append(look)
        model.status = StatusMessage("Saved Look “\(trimmed)”")
    }
}

// MARK: - Window

private struct WindowCard: View {
    let model: ShootModel

    var body: some View {
        InspectorCard("Window", systemImage: "macwindow", isActive: model.look.window == .safari) {
            EmptyView()
        } content: {
            FilledSegments("Window", selection: Binding(
                get: { model.look.window },
                set: { value in model.setLook(as: "Change Window") { $0.window = value } }
            ), segments: WindowStyle.allCases.map { .init(value: $0, title: $0.title) })

            if model.look.window == .safari {
                StackedControl("Appearance") {
                    FilledSegments("Appearance", selection: Binding(
                        get: { model.look.safari.appearance },
                        set: { value in model.setLook(as: "Change Window Appearance") { $0.safari.appearance = value } }
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
                if model.look.backdrop == .none {
                    Toggle("Shadow", isOn: Binding(
                        get: { model.look.safari.showsShadow },
                        set: { value in model.setLook(as: value ? "Show Shadow" : "Hide Shadow") { $0.safari.showsShadow = value } }
                    ))
                }
            }
        }
    }
}

// MARK: - Backdrop

private struct BackdropCard: View {
    let model: ShootModel

    var body: some View {
        InspectorCard("Backdrop", systemImage: "photo.on.rectangle", isActive: model.look.backdrop != .none) {
            EmptyView()
        } content: {
            FilledSegments("Backdrop", selection: Binding(
                get: { model.look.backdrop },
                set: { value in model.setLook(as: "Change Backdrop") { $0.backdrop = value } }
            ), segments: Backdrop.allCases.map { .init(value: $0, title: $0.title) })

            switch model.look.backdrop {
            case .none: EmptyView()
            case .canvas: canvasControls
            case .desktop: desktopControls
            }
        }
    }

    @ViewBuilder private var canvasControls: some View {
        Picker("Ratio", selection: Binding(
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
        InspectorSlider("Shadow", value: model.look.canvas.shadow, in: 0...1, default: 0.6) { value in
            model.beginGesture()
            model.look.canvas.shadow = value
        } commit: {
            model.endGesture(as: "Change Shadow")
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
        Picker("Display", selection: Binding(
            get: { model.look.desktop.displayID },
            set: { value in model.setLook(as: "Change Display") { $0.desktop.displayID = value } }
        )) {
            ForEach(SizePreset.builtIns.filter { $0.group == .mac }) { Text($0.name).tag($0.id) }
        }
        HStack {
            Button("Center") { model.centerDesktopWindow() }
            Button("Fill Desktop") { model.fillDesktop() }
        }
        Text("Drag the window’s toolbar to move it, or its edges to resize it.")
            .font(.callout)
            .foregroundStyle(.secondary)
        Picker("Menu Bar", selection: Binding(
            get: { model.look.desktop.menuBar },
            set: { value in model.setLook(as: "Change Menu Bar") { $0.desktop.menuBar = value } }
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

// MARK: - Background

private struct BackgroundCard: View {
    let model: ShootModel

    private let columns = [GridItem(.adaptive(minimum: 44), spacing: 6)]

    var body: some View {
        InspectorCard("Background", systemImage: "paintpalette", isActive: model.look.backdrop != .none) {
            EmptyView()
        } content: {
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
                Button("Image…") { Task { await model.chooseBackgroundImage() } }
            }
        }
        .disabled(model.look.backdrop == .none)
    }
}

// MARK: - Output

private struct OutputCard: View {
    @Bindable private var defaults = Defaults.shared

    var body: some View {
        InspectorCard("Output", systemImage: "square.and.arrow.down") {
            EmptyView()
        } content: {
            FilledSegments("Format", selection: $defaults.format,
                           segments: ImageFormat.allCases.map { .init(value: $0, title: $0.title) })
            if defaults.format != .png {
                InspectorSlider("Quality", value: defaults.jpegQuality, in: 0.5...1, default: 0.9) { value in
                    defaults.jpegQuality = value
                } commit: {}
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
