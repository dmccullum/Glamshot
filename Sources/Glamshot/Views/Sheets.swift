import GlamshotCore
import SwiftUI

/// Names the current Look and keeps it with the built-in ones.
struct SaveLookSheet: View {
    let model: ShootModel
    @State private var name = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Name", text: $name)
            } footer: {
                Text("Saves this window’s Safari window, backdrop and background. Choose it later from the Preset menu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 380)
        .fixedSize(horizontal: false, vertical: true)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save Preset") {
                    model.saveLook(named: name)
                    dismiss()
                }
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }
}

/// CSS selectors hidden while photographing, such as a cookie banner or chat button.
struct HideElementsSheet: View {
    let model: ShootModel
    @State private var selectors = ""
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            Section {
                TextField("Selectors", text: $selectors, prompt: Text("#cookie-banner, .chat-button"), axis: .vertical)
                    .lineLimit(3...6)
            } footer: {
                Text("Elements matching these CSS selectors are hidden on every page in this window, and in its images. Separate selectors with commas or new lines.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
        .frame(width: 420)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { selectors = model.capture.hiddenSelectors }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button("Hide Elements") {
                    model.setCapture(as: "Hide Elements") { $0.hiddenSelectors = selectors }
                    dismiss()
                }
            }
        }
    }
}
