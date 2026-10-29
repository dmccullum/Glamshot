import DMKit
import GlamshotCore
import SwiftUI

struct SettingsView: View {
    var body: some View {
        TabView {
            Tab("General", systemImage: "gearshape") { GeneralSettings() }
            Tab("Sizes", systemImage: "rectangle.dashed") { SizesSettings() }
            Tab("Looks", systemImage: "sparkles") { LooksSettings() }
        }
        .frame(width: DMLayout.settingsWidth)
    }
}

private struct GeneralSettings: View {
    @Bindable private var defaults = Defaults.shared

    var body: some View {
        Form {
            Section {
                TextField("File Name", text: $defaults.fileNameTemplate)
                Text("Use \(FileNaming.tokens.joined(separator: ", ")).")
                    .font(.callout)
                    .foregroundStyle(.secondary)
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
    @State private var selection: SizePreset.ID?

    var body: some View {
        Form {
            Section("Your Sizes") {
                if defaults.customPresets.isEmpty {
                    Text("Sizes you add appear in every window’s sidebar under Custom.")
                        .foregroundStyle(.secondary)
                }
                ForEach($defaults.customPresets) { $preset in
                    HStack {
                        TextField("Name", text: $preset.name).labelsHidden()
                        TextField("Width", value: $preset.width, format: .number).labelsHidden().frame(width: 64)
                        Text("×").foregroundStyle(.secondary)
                        TextField("Height", value: $preset.height, format: .number).labelsHidden().frame(width: 64)
                        Picker("Scale", selection: $preset.scale) {
                            ForEach(1...3, id: \.self) { Text("\($0)×").tag($0) }
                        }
                        .labelsHidden()
                        .frame(width: 64)
                        Button {
                            defaults.customPresets.removeAll { $0.id == preset.id }
                        } label: {
                            Label("Delete \(preset.name)", systemImage: "minus.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Delete “\(preset.name)”")
                    }
                    .monospacedDigit()
                }
            }
            Section {
                Button("Add Size") {
                    defaults.customPresets.append(SizePreset(name: "Custom \(defaults.customPresets.count + 1)", group: .custom,
                                                             width: 1440, height: 900, scale: 2))
                }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}

private struct LooksSettings: View {
    @Bindable private var defaults = Defaults.shared

    var body: some View {
        Form {
            Section("Built In") {
                ForEach(Look.builtIns) { look in
                    LabeledContent(look.name, value: look.summary)
                }
            }
            Section("Your Looks") {
                if defaults.customLooks.isEmpty {
                    Text("Choose Save Look… in a window’s inspector to keep its window, backdrop and background here.")
                        .foregroundStyle(.secondary)
                }
                ForEach($defaults.customLooks) { $look in
                    HStack {
                        TextField("Name", text: $look.name).labelsHidden()
                        Text(look.summary).foregroundStyle(.secondary)
                        Button {
                            defaults.customLooks.removeAll { $0.id == look.id }
                        } label: {
                            Label("Delete \(look.name)", systemImage: "minus.circle")
                        }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Delete “\(look.name)”")
                    }
                }
                .onMove { defaults.customLooks.move(fromOffsets: $0, toOffset: $1) }
            }
        }
        .formStyle(.grouped)
        .fixedSize(horizontal: false, vertical: true)
    }
}
