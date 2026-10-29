import GlamshotCore
import SwiftUI

/// Sizes, grouped by device. Selecting one sets the viewport; the checkboxes pick sizes for
/// Export Sizes….
struct SidebarView: View {
    @Bindable var model: ShootModel
    @Bindable private var defaults = Defaults.shared

    var body: some View {
        List(selection: Binding(
            get: { model.currentPreset?.id },
            set: { id in
                if let id, let preset = defaults.allPresets.first(where: { $0.id == id }) { model.choose(preset) }
            }
        )) {
            ForEach(SizePreset.Group.allCases, id: \.self) { group in
                let presets = defaults.allPresets.filter { $0.group == group }
                if !presets.isEmpty {
                    Section(group.title) {
                        ForEach(presets) { preset in
                            row(preset).tag(preset.id)
                        }
                    }
                }
            }
        }
        .disabled(model.look.backdrop == .desktop)
        .safeAreaInset(edge: .bottom) {
            if model.look.backdrop == .desktop {
                Text("On a desktop, resize the window to set the viewport.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .padding(12)
            }
        }
    }

    private func row(_ preset: SizePreset) -> some View {
        HStack(spacing: 8) {
            Toggle(isOn: Binding(
                get: { model.exportSizeIDs.contains(preset.id) },
                set: { isOn in
                    if isOn { model.exportSizeIDs.insert(preset.id) } else { model.exportSizeIDs.remove(preset.id) }
                }
            )) {
                EmptyView()
            }
            .toggleStyle(.checkbox)
            .labelsHidden()
            .help("Include in Export Sizes…")
            VStack(alignment: .leading, spacing: 1) {
                Text(preset.name)
                Text("\(preset.dimensions) · \(preset.scale)×")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }
        }
        .accessibilityElement(children: .combine)
    }
}
