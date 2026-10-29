import AppKit
import DMKit
import GlamshotCore
import SwiftUI

/// Four cards: the image's size, how wide the page lays out, the frame (picked from four tiles, with
/// only that frame's controls below), and the Safari window's chrome when one is drawn. Numbers sit
/// in the controls rather than in notes, and controls that don't apply aren't shown; the menu bar
/// keeps them, disabled.
struct InspectorView: View {
    @Bindable var model: ShootModel

    var body: some View {
        ScrollView {
            VStack(spacing: DMLayout.inspectorSpacing) {
                SizeCard(model: model)
                PageCard(model: model)
                FrameCard(model: model)
                if showsWindowCard {
                    WindowCard(model: model)
                }
            }
            .padding(DMLayout.inspectorPadding)
        }
    }

    private var showsWindowCard: Bool {
        switch model.effectiveLook.frameStyle {
        case .safari, .desktop: true
        case .canvas: !model.capture.fullPage
        case .page: false
        }
    }
}

// MARK: - Size

private struct SizeCard: View {
    let model: ShootModel
    @State private var width = ""
    @State private var height = ""
    @FocusState private var widthFocused: Bool

    var body: some View {
        InspectorCard("Size", systemImage: "aspectratio") {
            Text(pixelSize)
                .font(.callout)
                .foregroundStyle(.secondary)
                .monospacedDigit()
        } content: {
            Menu {
                ForEach(SizePreset.Group.allCases, id: \.self) { group in
                    let presets = Defaults.shared.presets.filter { $0.group == group }
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
                Divider()
                Toggle("Custom", isOn: Binding(get: { model.isCustomSize }, set: { _ in model.chooseCustomSize() }))
            } label: {
                Text(model.currentPreset?.name ?? "Custom")
            }
            .fixedSize()
            .frame(maxWidth: .infinity, alignment: .leading)

            HStack(spacing: 6) {
                TextField("Width", text: $width)
                    .onSubmit(commit)
                    .focused($widthFocused)
                Text("×").foregroundStyle(.secondary)
                if model.capture.fullPage {
                    // The page's length sets the height.
                    TextField("Height", text: .constant("Full"))
                        .disabled(true)
                        .help("A full page is as tall as the page")
                } else {
                    TextField("Height", text: $height).onSubmit(commit)
                }
                Text("pt").foregroundStyle(.secondary)
                Picker("Scale", selection: Binding(
                    get: { model.capture.scale },
                    set: { value in model.setCapture(as: "Change Scale") { $0.scale = value } }
                )) {
                    ForEach(1...3, id: \.self) { Text("\($0)×").tag($0) }
                }
                .labelsHidden()
                .fixedSize()
                .help("Pixels per point")
            }
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
        }
        .onAppear(perform: syncFields)
        .onChange(of: model.capture) { syncFields() }
        .onChange(of: model.focusSizeRequest) { widthFocused = true }
    }

    /// The saved image's size in pixels.
    private var pixelSize: String {
        let height = model.capture.fullPage ? model.fullPagePreview?.pointSize.height : nil
        let layout = FrameLayout.make(output: model.capture.outputSize, look: model.effectiveLook, pageHeight: height)
        let scale = CGFloat(model.capture.scale)
        let width = Int(layout.canvasSize.width * scale)
        if model.capture.fullPage, height == nil { return "\(width) px wide" }
        return "\(width.formatted()) × \(Int(layout.canvasSize.height * scale).formatted()) px"
    }

    private func syncFields() {
        width = "\(model.capture.width)"
        height = "\(model.capture.height)"
    }

    private func commit() {
        let h = model.capture.fullPage ? model.capture.height : Int(height) ?? 0
        guard let w = Int(width), (200...8000).contains(w), (200...8000).contains(h) else {
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

    /// The page's room in points; at 100% zoom it lays out at this width.
    private var roomWidth: Double { Double(model.pageSize.width) }

    var body: some View {
        InspectorCard("Page", systemImage: "doc.richtext") {
            Picker("Appearance", selection: Binding(
                get: { model.capture.appearance },
                set: { value in model.setCapture(as: "Change Appearance") { $0.appearance = value } }
            )) {
                Image(systemName: "sun.max").tag(CaptureOptions.Appearance.light)
                    .accessibilityLabel("Light")
                Image(systemName: "moon").tag(CaptureOptions.Appearance.dark)
                    .accessibilityLabel("Dark")
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .fixedSize()
            .help("Light or dark mode for the page and Safari’s window")
        } content: {
            // The zoom, shown as the width the page lays out at: wider means smaller.
            InspectorSlider("Page Width", value: roomWidth / model.capture.zoom,
                            in: roomWidth...(roomWidth / CaptureOptions.zoomRange.lowerBound),
                            default: roomWidth,
                            format: .init(unit: .init(symbol: "px", spokenName: "pixels"), step: 10)) { value in
                model.beginGesture()
                model.capture.zoom = min(max(roomWidth / value, CaptureOptions.zoomRange.lowerBound), 1)
            } commit: {
                model.endGesture(as: "Change Page Width")
            }
            .help("How wide a browser window the page lays out in. Wider shows more of a desktop layout, drawn smaller.")
        }
    }
}

// MARK: - Frame

private struct FrameCard: View {
    let model: ShootModel

    private var style: FrameStyle { model.effectiveLook.frameStyle }

    var body: some View {
        InspectorCard("Frame", systemImage: "macwindow.on.rectangle") {
            EmptyView()
        } content: {
            FrameTiles(model: model)

            switch style {
            case .page:
                EmptyView()
            case .safari:
                shadowSlider
            case .canvas:
                BackgroundPicker(model: model)
                paddingSlider
                if model.effectiveLook.window == .none {
                    InspectorSlider("Corner Radius", value: model.look.canvas.cornerRadius, in: 0...40, default: 14,
                                    format: .init(unit: .points), snapsToStep: true) { value in
                        model.beginGesture()
                        model.look.canvas.cornerRadius = value
                    } commit: {
                        model.endGesture(as: "Change Corner Radius")
                    }
                }
                shadowSlider
            case .desktop:
                BackgroundPicker(model: model)
                DesktopWindowSize(model: model)
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

    /// Auto Padding picks the amount from the size; off, the slider sets it. While Auto is on the
    /// slider is dimmed and shows the automatic amount.
    @ViewBuilder private var paddingSlider: some View {
        SwitchRow("Auto Padding", isOn: Binding(
            get: { model.look.canvas.autoPadding },
            set: { value in
                model.setLook(as: value ? "Turn On Auto Padding" : "Turn Off Auto Padding") { look in
                    // Turning Auto off starts from the amount it was using.
                    if !value { look.canvas.padding = FrameLayout.automaticPadding(for: model.capture.outputSize) }
                    look.canvas.autoPadding = value
                }
            }
        ))
        InspectorSlider("Padding", value: model.effectivePadding, in: 0...400,
                        format: .init(unit: .points), snapsToStep: true) { value in
            model.beginGesture()
            model.look.canvas.padding = value
        } commit: {
            model.endGesture(as: "Change Padding")
        }
        .disabled(model.look.canvas.autoPadding)
    }
}

/// Four thumbnails, one per frame. Frames the size or mode can't use aren't offered.
private struct FrameTiles: View {
    let model: ShootModel

    var body: some View {
        HStack(spacing: 8) {
            ForEach(model.availableFrameStyles, id: \.self) { style in
                let selected = model.effectiveLook.frameStyle == style
                Button {
                    model.setFrameStyle(style)
                } label: {
                    VStack(spacing: 4) {
                        FrameThumbnail(style: style)
                            .frame(height: 38)
                            .frame(maxWidth: .infinity)
                            .padding(4)
                            .background {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .fill(selected ? Color.accentColor.opacity(0.18) : Color.primary.opacity(0.05))
                            }
                            .overlay {
                                RoundedRectangle(cornerRadius: 8, style: .continuous)
                                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.1), lineWidth: selected ? 2 : 1)
                            }
                        Text(style.title)
                            .font(.caption)
                            .foregroundStyle(selected ? .primary : .secondary)
                    }
                }
                .buttonStyle(.plain)
                .accessibilityLabel(style.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
        }
    }
}

/// A tiny drawing of each frame.
private struct FrameThumbnail: View {
    let style: FrameStyle

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                switch style {
                case .page:
                    page.frame(width: size.width * 0.78, height: size.height * 0.92)
                case .safari:
                    window.frame(width: size.width * 0.82, height: size.height * 0.92)
                case .canvas:
                    backdrop
                    window.frame(width: size.width * 0.6, height: size.height * 0.62)
                case .desktop:
                    backdrop
                    VStack(spacing: 0) {
                        Rectangle().fill(.white.opacity(0.7)).frame(height: 2)
                        Spacer()
                    }
                    window.frame(width: size.width * 0.62, height: size.height * 0.6).offset(y: 2)
                }
            }
            .frame(width: size.width, height: size.height)
        }
    }

    private var page: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous).fill(Color.primary.opacity(0.35))
    }

    private var window: some View {
        VStack(spacing: 0) {
            HStack(spacing: 1.5) {
                ForEach(0..<3) { _ in Circle().frame(width: 2.5, height: 2.5) }
                Spacer(minLength: 0)
            }
            .foregroundStyle(Color.primary.opacity(0.5))
            .padding(.horizontal, 3)
            .frame(height: 6)
            .background(Color.primary.opacity(0.18))
            Rectangle().fill(Color.primary.opacity(0.35))
        }
        .clipShape(RoundedRectangle(cornerRadius: 3, style: .continuous))
    }

    private var backdrop: some View {
        RoundedRectangle(cornerRadius: 4, style: .continuous)
            .fill(LinearGradient(colors: [Color(hex: "#F3AC91") ?? .pink, Color(hex: "#7655A3") ?? .purple],
                                 startPoint: .topLeading, endPoint: .bottomTrailing))
    }
}

/// The desktop window's size in points, live as it's dragged, with Center and Fill.
private struct DesktopWindowSize: View {
    let model: ShootModel
    @State private var width = ""
    @State private var height = ""

    var body: some View {
        StackedControl("Window Size") {
            HStack(spacing: 6) {
                TextField("Width", text: $width).onSubmit(commit)
                Text("×").foregroundStyle(.secondary)
                TextField("Height", text: $height).onSubmit(commit)
                Text("pt").foregroundStyle(.secondary)
                Button { model.centerDesktopWindow() } label: {
                    Label("Center Window", systemImage: "align.horizontal.center")
                }
                .help("Center Window")
                Button { model.fillDesktop() } label: {
                    Label("Fill Desktop", systemImage: "arrow.up.left.and.arrow.down.right")
                }
                .help("Fill Desktop")
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .textFieldStyle(.roundedBorder)
            .monospacedDigit()
        }
        .onAppear(perform: sync)
        .onChange(of: model.look.desktop) { sync() }
        .onChange(of: model.capture.outputSize) { sync() }
    }

    private func sync() {
        let size = model.desktopWindowSize
        width = "\(Int(size.width))"
        height = "\(Int(size.height))"
    }

    private func commit() {
        guard let w = Double(width), let h = Double(height) else { return sync() }
        model.beginGesture()
        model.desktopWindowSize = CGSize(width: w, height: h)
        model.endGesture(as: "Resize Window")
        sync()
    }
}

// MARK: - Safari window

private struct WindowCard: View {
    let model: ShootModel

    private var isOn: Bool { model.look.window == .safari }
    private var device: SafariOptions.Device { model.effectiveLook.safari.device }
    /// Only a canvas makes the window optional.
    private var hasSwitch: Bool { model.effectiveLook.frameStyle == .canvas }

    var body: some View {
        InspectorCard("Safari Window", systemImage: "macwindow", isActive: isOn || !hasSwitch) {
            if hasSwitch {
                Toggle("Safari Window", isOn: Binding(
                    get: { isOn },
                    set: { value in
                        model.setLook(as: value ? "Show Safari Window" : "Hide Safari Window") { $0.window = value ? .safari : .none }
                    }
                ))
                .toggleStyle(.switch)
                .labelsHidden()
                .controlSize(.small)
            }
        } content: {
            if isOn {
                LabeledRow("Address") {
                    Picker("Address", selection: Binding(
                        get: { model.look.safari.address },
                        set: { value in model.setLook(as: "Change Address") { $0.safari.address = value } }
                    )) {
                        ForEach(SafariOptions.Address.allCases, id: \.self) { Text($0 == .fullURL ? "Full Address" : $0.title).tag($0) }
                    }
                    .labelsHidden()
                    .fixedSize()
                }
                if model.look.safari.address == .custom {
                    CustomAddressField(model: model)
                }
                if device == .iPhone {
                    SwitchRow("Minimized Bar", isOn: Binding(
                        get: { model.look.safari.phoneBar == .minimized },
                        set: { value in model.setLook(as: "Change Address Bar") { $0.safari.phoneBar = value ? .minimized : .full } }
                    ))
                    .help("Safari’s address bar as it shrinks after you scroll")
                } else {
                    SwitchRow("Tab Bar", isOn: Binding(
                        get: { model.look.safari.showsTabBar },
                        set: { value in model.setLook(as: value ? "Show Tab Bar" : "Hide Tab Bar") { $0.safari.showsTabBar = value } }
                    ))
                }
            }
        }
    }
}

/// The text a Custom address shows; it belongs to the window, not the frame settings.
private struct CustomAddressField: View {
    @Bindable var model: ShootModel
    @State private var text = ""

    var body: some View {
        TextField("yourbrand.com", text: $text)
            .textFieldStyle(.roundedBorder)
            .onSubmit { model.customAddress = text.trimmingCharacters(in: .whitespaces) }
            .onAppear { text = model.customAddress }
            .onChange(of: model.customAddress) { text = model.customAddress }
            .help("Shown in the window instead of the page’s address. You can also click the address in the window.")
    }
}

// MARK: - Background

/// Eight gradients, a color tile and an image tile in a 5 × 2 grid, with Shuffle beside the title.
private struct BackgroundPicker: View {
    let model: ShootModel

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 6), count: 5)

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("Background")
                Spacer()
                if model.look.background.gradientName != nil {
                    Button { model.shuffleBackground() } label: { Label("Shuffle", systemImage: "shuffle") }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Shuffle: a new arrangement of the same colors")
                }
            }
            LazyVGrid(columns: columns, spacing: 6) {
                ForEach(GradientLibrary.entries) { entry in
                    let selected = model.look.background.gradientName == entry.name
                    Button {
                        model.setLook(as: "Change Background") { $0.background = .gradient(name: entry.name, seed: 0) }
                    } label: {
                        tile(selected: selected) { BackgroundView(fill: .gradient(name: entry.name, seed: 0)) }
                    }
                    .buttonStyle(.plain)
                    .help(entry.name)
                    .accessibilityLabel(entry.name)
                    .accessibilityAddTraits(selected ? .isSelected : [])
                }
                Button { BackgroundColorPanel.shared.show(for: model) } label: {
                    tile(selected: model.look.background.color != nil) { symbolTile("paintpalette") }
                }
                .buttonStyle(.plain)
                .help("Color…")
                .accessibilityLabel("Color…")
                .accessibilityAddTraits(model.look.background.color != nil ? .isSelected : [])
                Button { Task { await model.chooseBackgroundImage() } } label: {
                    tile(selected: isImage) { symbolTile("photo") }
                }
                .buttonStyle(.plain)
                .help("Image…")
                .accessibilityLabel("Image…")
            }
        }
    }

    private var isImage: Bool {
        if case .image = model.look.background { return true }
        return false
    }

    /// A gray tile with a symbol, for the choices that open a panel.
    private func symbolTile(_ symbol: String) -> some View {
        ZStack {
            Color.primary.opacity(0.06)
            Image(systemName: symbol).foregroundStyle(.secondary)
        }
    }

    private func tile<Content: View>(selected: Bool, @ViewBuilder content: () -> Content) -> some View {
        content()
            .frame(height: 30)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .strokeBorder(selected ? Color.accentColor : Color.primary.opacity(0.12), lineWidth: selected ? 2 : 1)
            }
    }
}

/// The shared color panel, setting the background color. Each burst of changes is one undo step.
final class BackgroundColorPanel: NSObject {
    static let shared = BackgroundColorPanel()
    private weak var model: ShootModel?
    private var settle: Task<Void, Never>?

    func show(for model: ShootModel) {
        finish()
        self.model = model
        let panel = NSColorPanel.shared
        panel.setTarget(nil)
        panel.setAction(nil)
        panel.showsAlpha = false
        panel.isContinuous = true
        panel.color = model.look.background.color.map { NSColor($0) } ?? .white
        panel.setTarget(self)
        panel.setAction(#selector(colorChanged(_:)))
        panel.orderFront(nil)
        // Choosing the tile picks the panel's color, as clicking a color well would.
        colorChanged(panel)
    }

    @objc private func colorChanged(_ panel: NSColorPanel) {
        guard let model else { return }
        model.beginGesture()
        model.look.background = .color(hex: panel.color.hexString)
        settle?.cancel()
        settle = Task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled else { return }
            model.endGesture(as: "Change Background")
        }
    }

    private func finish() {
        settle?.cancel()
        model?.endGesture(as: "Change Background")
    }
}

// MARK: - Rows

/// A title at the left and its control at the right edge of the card.
private struct LabeledRow<Control: View>: View {
    let title: String
    @ViewBuilder let control: () -> Control

    init(_ title: String, @ViewBuilder control: @escaping () -> Control) {
        self.title = title
        self.control = control
    }

    var body: some View {
        HStack {
            Text(title)
            Spacer(minLength: 8)
            control()
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
