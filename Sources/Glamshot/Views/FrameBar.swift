import DMKit
import GlamshotCore
import SwiftUI

/// The glass bar under the canvas: the four frames, then the background and Shuffle when there's
/// a backdrop. Frames the size or mode can't use aren't offered; the Frame menu keeps them, disabled.
struct FrameBar: View {
    let model: ShootModel
    @State private var isChoosingBackground = false

    var body: some View {
        FloatingBar {
            ForEach(model.availableFrameStyles, id: \.self) { style in
                let selected = model.effectiveLook.frameStyle == style
                Button { model.chooseFrame(style) } label: {
                    Label(style.title, systemImage: style.systemImage)
                }
                .buttonStyle(.floatingBar)
                .foregroundStyle(selected ? Color.accentColor : Color.primary)
                .background(Capsule().fill(Color.primary.opacity(selected ? 0.14 : 0)))
                .help(style.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
            }
            if model.effectiveLook.backdrop != .none {
                Divider().frame(height: 18)
                Button { isChoosingBackground = true } label: {
                    Label {
                        Text("Background")
                    } icon: {
                        BackgroundView(fill: model.look.background)
                            .frame(width: 18, height: 18)
                            .clipShape(Circle())
                            .overlay { Circle().strokeBorder(Color.primary.opacity(0.25), lineWidth: 1) }
                    }
                }
                .buttonStyle(.floatingBar)
                .help("Background")
                .accessibilityLabel("Background")
                .popover(isPresented: $isChoosingBackground, arrowEdge: .top) {
                    BackgroundPicker(model: model)
                        .frame(width: 260)
                        .padding(14)
                }
                if model.look.background.gradientName != nil {
                    Button { model.shuffleBackground() } label: { Label("Shuffle", systemImage: "shuffle") }
                        .buttonStyle(.floatingBar)
                        .help("Shuffle: a new arrangement of the same colors")
                }
            }
        }
    }
}

extension FrameStyle {
    var systemImage: String {
        switch self {
        case .page: "doc.text"
        case .safari: "macwindow"
        case .canvas: "inset.filled.center.rectangle"
        case .desktop: "menubar.dock.rectangle"
        }
    }
}
