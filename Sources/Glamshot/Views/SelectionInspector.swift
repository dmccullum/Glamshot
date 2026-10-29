import DMKit
import GlamshotCore
import SwiftUI

/// Size and Page, always, then the card for what's selected on the canvas: the backdrop or the
/// Safari window. The frame and background are picked from the bar over the canvas.
struct SelectionInspector: View {
    @Bindable var model: ShootModel

    var body: some View {
        ScrollView {
            VStack(spacing: DMLayout.inspectorSpacing) {
                SizeCard(model: model)
                PageCard(model: model)
                switch model.selectedObject {
                case .backdrop: BackdropCard(model: model)
                case .window: SelectedWindowCard(model: model)
                case .none: EmptyView()
                }
            }
            .padding(DMLayout.inspectorPadding)
        }
    }
}

// MARK: - Backdrop

/// The canvas or desktop behind the page: its background, and on a canvas the room around the
/// window, the window itself, the page's corners and the shadow.
private struct BackdropCard: View {
    let model: ShootModel

    private var isDesktop: Bool { model.effectiveLook.backdrop == .desktop }

    var body: some View {
        InspectorCard(isDesktop ? "Desktop" : "Canvas",
                      systemImage: isDesktop ? "menubar.dock.rectangle" : "inset.filled.center.rectangle") {
            EmptyView()
        } content: {
            BackgroundPicker(model: model)
            if !isDesktop {
                // A full page never has a window, so there's nothing to switch.
                if !model.capture.fullPage {
                    SwitchRow("Safari Window", isOn: Binding(
                        get: { model.look.window == .safari },
                        set: { value in
                            model.setLook(as: value ? "Show Safari Window" : "Hide Safari Window") { $0.window = value ? .safari : .none }
                        }
                    ))
                }
                PaddingSlider(model: model)
                if model.effectiveLook.window == .none {
                    InspectorSlider("Corner Radius", value: model.look.canvas.cornerRadius, in: 0...40, default: 14,
                                    format: .init(unit: .points), snapsToStep: true) { value in
                        model.beginGesture()
                        model.look.canvas.cornerRadius = value
                    } commit: {
                        model.endGesture(as: "Change Corner Radius")
                    }
                }
                ShadowSlider(model: model)
            }
        }
    }
}

// MARK: - Window

/// The Safari window: its size on a desktop, the address it shows, and its bars.
private struct SelectedWindowCard: View {
    let model: ShootModel

    private var look: Look { model.effectiveLook }

    var body: some View {
        InspectorCard("Safari Window", systemImage: "macwindow") {
            EmptyView()
        } content: {
            if look.backdrop == .desktop {
                DesktopWindowSize(model: model)
            }
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
            if look.safari.device == .iPhone {
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
            // On a canvas the shadow sits with the padding; with no backdrop the window is all there is.
            if look.backdrop == .none {
                ShadowSlider(model: model)
            }
        }
    }
}

// MARK: - Sliders

private struct ShadowSlider: View {
    let model: ShootModel

    var body: some View {
        InspectorSlider("Shadow", value: model.look.shadow, in: 0...1, default: 0.7, format: .percent) { value in
            model.beginGesture()
            model.look.shadow = value
        } commit: {
            model.endGesture(as: "Change Shadow")
        }
    }
}

/// Its default is Auto; dragging sets a fixed amount, and double-clicking the title returns to Auto.
/// The canvas's edge handles set the same value.
private struct PaddingSlider: View {
    let model: ShootModel

    var body: some View {
        let automatic = FrameLayout.automaticPadding(for: model.capture.outputSize)
        InspectorSlider(model.look.canvas.autoPadding ? "Padding · Auto" : "Padding",
                        value: model.effectivePadding, in: 0...400, default: automatic,
                        format: .init(unit: .points), snapsToStep: true) { value in
            model.beginGesture()
            model.setPadding(value)
        } commit: {
            model.endGesture(as: "Change Padding")
        }
        .help("Double-click the title to return to automatic padding, or drag the canvas’s edges")
    }
}
