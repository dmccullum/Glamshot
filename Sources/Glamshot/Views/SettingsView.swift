import DMKit
import GlamshotCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Sizes", systemImage: "rectangle.dashed") { SizesSettings() }
        }
        .frame(width: DMLayout.settingsWidth)
    }
}

private struct GeneralSettings: View {
    @Bindable private var defaults = Defaults.shared

    var body: some View {
        Form {
            Section {
                FileNameSetting(template: $defaults.fileNameTemplate)
            }
            Section {
                Picker("Format", selection: $defaults.format) {
                    ForEach(ImageFormat.allCases) { Text($0.title).tag($0) }
                }
                if defaults.format != .png {
                    Slider(value: $defaults.jpegQuality, in: 0.5...1) {
                        Text("Quality")
                    } minimumValueLabel: {
                        Text("Smaller")
                    } maximumValueLabel: {
                        Text("Best")
                    }
                }
                LabeledContent("Save Folder") {
                    Text(defaults.saveFolder?.lastPathComponent ?? "Ask Each Time")
                        .foregroundStyle(.secondary)
                }
            }
            Section {
                Picker("Wait After Loading", selection: $defaults.waitAfterLoading) {
                    Text("None").tag(0.0)
                    Text("0.5 Seconds").tag(0.5)
                    Text("1 Second").tag(1.0)
                    Text("2 Seconds").tag(2.0)
                    Text("5 Seconds").tag(5.0)
                }
                Text("Time for animations and late-loading content to finish before Glamshot photographs the page.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct SizesSettings: View {
    @Bindable private var defaults = Defaults.shared
    @State private var selection: Set<SizePreset.ID> = []
    @Environment(\.undoManager) private var undoManager

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            List(selection: $selection) {
                ForEach(SizePreset.Group.allCases, id: \.self) { group in
                    let indices = defaults.presets.indices.filter { defaults.presets[$0].group == group }
                    if !indices.isEmpty {
                        Section(group.title) {
                            ForEach(indices, id: \.self) { index in
                                SizeRow(preset: $defaults.presets[index])
                                    .tag(defaults.presets[index].id)
                            }
                            .onMove { from, to in move(in: group, from: from, to: to) }
                        }
                    }
                }
            }
            .listStyle(.inset)
            .alternatingRowBackgrounds()
            .onDeleteCommand { delete(selection) }
            .frame(height: 400)

            Divider()
            HStack(spacing: 0) {
                Button { add() } label: { Label("Add Size", systemImage: "plus").frame(width: 24, height: 20) }
                    .help("Add a size")
                Divider().frame(height: 16)
                Button { delete(selection) } label: { Label("Delete", systemImage: "minus").frame(width: 24, height: 20) }
                    .disabled(selection.isEmpty)
                    .help("Delete the selected sizes")
                Spacer()
                Button("Restore Built-In Sizes") { restore() }
                    .controlSize(.small)
                    .disabled(!defaults.builtInsChanged)
                    .help("Puts back every built-in size as it shipped; your own sizes stay")
                    .padding(.trailing, 8)
            }
            .labelStyle(.iconOnly)
            .buttonStyle(.borderless)
            .padding(4)
        }
        .padding(20)
    }

    private func change(_ name: String, _ work: () -> Void) {
        let before = defaults.presets
        work()
        undoManager?.registerUndo(withTarget: defaults) { defaults in
            let after = defaults.presets
            defaults.presets = before
            undoManager?.registerUndo(withTarget: defaults) { $0.presets = after }
        }
        undoManager?.setActionName(name)
    }

    private func add() {
        let preset = SizePreset(name: "New Size", group: .custom, width: 1440, height: 900, scale: 2)
        change("Add Size") { defaults.presets.append(preset) }
        selection = [preset.id]
    }

    private func delete(_ ids: Set<SizePreset.ID>) {
        guard !ids.isEmpty else { return }
        change(ids.count == 1 ? "Delete Size" : "Delete Sizes") { defaults.presets.removeAll { ids.contains($0.id) } }
        selection = []
    }

    private func restore() {
        change("Restore Built-In Sizes") { defaults.restoreBuiltInSizes() }
    }

    /// Reorders within one group's section; offsets are the section's own.
    private func move(in group: SizePreset.Group, from source: IndexSet, to destination: Int) {
        var section = defaults.presets.filter { $0.group == group }
        section.move(fromOffsets: source, toOffset: destination)
        var iterator = section.makeIterator()
        change("Move Size") {
            defaults.presets = defaults.presets.map { $0.group == group ? iterator.next()! : $0 }
        }
    }
}

/// One size: its name, width × height in points, and pixel scale, each editable in place.
private struct SizeRow: View {
    @Binding var preset: SizePreset

    var body: some View {
        HStack {
            TextField("Name", text: $preset.name)
                .labelsHidden()
            TextField("Width", value: $preset.width, format: .number.grouping(.never))
                .labelsHidden()
                .multilineTextAlignment(.trailing)
                .frame(width: 56)
            Text("×").foregroundStyle(.secondary)
            TextField("Height", value: $preset.height, format: .number.grouping(.never))
                .labelsHidden()
                .frame(width: 56)
            Text("pt").foregroundStyle(.secondary)
            Picker("Scale", selection: $preset.scale) {
                ForEach(1...3, id: \.self) { Text("\($0)×").tag($0) }
            }
            .labelsHidden()
            .frame(width: 60)
        }
        .monospacedDigit()
        .accessibilityElement(children: .contain)
        .accessibilityLabel(preset.name)
    }
}
