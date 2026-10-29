import GlamshotCore
import SwiftUI

/// Picks the sizes to render, then asks for a folder.
struct ExportSizesSheet: View {
    @Bindable var model: ShootModel
    @Environment(\.dismiss) private var dismiss

    private var count: Int { model.exportSizeIDs.count }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Export Sizes")
                .font(.headline)
                .padding([.horizontal, .top], 20)
            Text("Each checked size is photographed in the current Look and saved to one folder. A desktop backdrop becomes a canvas, since its window sets its own size.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 20)
                .padding(.top, 4)
            List {
                ForEach(SizePreset.Group.allCases, id: \.self) { group in
                    let presets = Defaults.shared.allPresets.filter { $0.group == group }
                    if !presets.isEmpty {
                        Section(group.title) {
                            ForEach(presets) { preset in
                                Toggle(isOn: Binding(
                                    get: { model.exportSizeIDs.contains(preset.id) },
                                    set: { isOn in
                                        if isOn { model.exportSizeIDs.insert(preset.id) } else { model.exportSizeIDs.remove(preset.id) }
                                    }
                                )) {
                                    HStack {
                                        Text(preset.name)
                                        Spacer()
                                        Text("\(preset.dimensions) · \(preset.scale)×")
                                            .foregroundStyle(.secondary)
                                            .monospacedDigit()
                                    }
                                }
                                .toggleStyle(.checkbox)
                            }
                        }
                    }
                }
            }
            .frame(height: 340)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(count == 1 ? "Export 1 Image…" : "Export \(count) Images…") {
                    dismiss()
                    Task {
                        try? await Task.sleep(for: .milliseconds(300))
                        await model.exportSizes()
                    }
                }
                .keyboardShortcut(.defaultAction)
                .disabled(count == 0)
            }
            .padding(20)
        }
        .frame(width: 440)
    }
}
