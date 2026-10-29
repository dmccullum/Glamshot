import AppKit
import DMKit
import GlamshotCore
import SwiftUI

/// The whole canvas, under the live page: a click on the backdrop margin selects the backdrop.
/// Where there's no backdrop, a click there clears the selection.
struct BackdropTarget: View {
    let model: ShootModel
    let layout: FrameLayout
    let scale: CGFloat

    var body: some View {
        Color.clear
            .contentShape(Rectangle())
            .frame(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)
            .onTapGesture { model.select(.backdrop) }
            .accessibilityHidden(true)
    }
}

/// The Safari window's chrome above the page: a click there selects the window. A desktop's
/// window is selected by `DesktopWindowHandles`, which also moves it.
struct WindowChromeTarget: View {
    let model: ShootModel
    let layout: FrameLayout
    let scale: CGFloat

    var body: some View {
        let rect = layout.windowRect
        Color.clear
            .contentShape(Rectangle())
            .frame(width: rect.width * scale, height: layout.chromeHeight * scale)
            .offset(x: rect.minX * scale, y: rect.minY * scale)
            .onTapGesture { model.select(.window) }
            .accessibilityHidden(true)
    }
}

/// What the selection looks like on the canvas, over everything: an outline around the selected
/// window, or around a selected backdrop with handles at the padding's edges. Drawn on screen
/// only; nothing here is part of the saved image.
struct CanvasSelectionOverlay: View {
    let model: ShootModel
    let layout: FrameLayout
    let scale: CGFloat

    private var look: Look { model.effectiveLook }

    var body: some View {
        switch model.selectedObject {
        case .window:
            windowOutline
        case .backdrop:
            Rectangle()
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: layout.canvasSize.width * scale, height: layout.canvasSize.height * scale)
                .allowsHitTesting(false)
            if look.backdrop == .canvas {
                PaddingHandles(model: model, layout: layout, scale: scale)
            }
        case .none:
            EmptyView()
        }
    }

    private var windowOutline: some View {
        let rect = layout.windowRect.insetBy(dx: -3 / scale, dy: -3 / scale)
        let radius = ShotView<EmptyView>.cornerRadius(look: look, layout: layout) * scale + 3
        return ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: radius, style: .continuous)
                .strokeBorder(Color.accentColor, lineWidth: 2)
                .frame(width: rect.width * scale, height: rect.height * scale)
                .offset(x: rect.minX * scale, y: rect.minY * scale)
            // A desktop window resizes from its corners and edges, so it shows corner knobs.
            if look.backdrop == .desktop {
                ForEach(Array(corners(of: rect).enumerated()), id: \.offset) { _, point in
                    Knob()
                        .frame(width: 8, height: 8)
                        .offset(x: point.x * scale - 4, y: point.y * scale - 4)
                }
            }
        }
        .allowsHitTesting(false)
    }

    private func corners(of rect: CGRect) -> [CGPoint] {
        [CGPoint(x: rect.minX, y: rect.minY), CGPoint(x: rect.maxX, y: rect.minY),
         CGPoint(x: rect.minX, y: rect.maxY), CGPoint(x: rect.maxX, y: rect.maxY)]
    }
}

/// A selection handle: white with an accent edge.
private struct Knob: View {
    var body: some View {
        RoundedRectangle(cornerRadius: 2, style: .continuous)
            .fill(.white)
            .overlay { RoundedRectangle(cornerRadius: 2, style: .continuous).strokeBorder(Color.accentColor, lineWidth: 1) }
            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5)
    }
}

/// A dashed guide where the padding ends and a handle on each edge. Dragging any handle sets the
/// padding on all four sides, with its amount in a badge; it pulls to Auto as it passes.
private struct PaddingHandles: View {
    let model: ShootModel
    let layout: FrameLayout
    let scale: CGFloat

    @State private var drag: (padding: CGFloat, scale: CGFloat)?
    @State private var isAutomatic = false

    var body: some View {
        let rect = layout.windowRect
        ZStack(alignment: .topLeading) {
            Rectangle()
                .strokeBorder(Color.white.opacity(0.8), style: StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .frame(width: rect.width * scale, height: rect.height * scale)
                .offset(x: rect.minX * scale, y: rect.minY * scale)
                .allowsHitTesting(false)

            ForEach(FrameLayout.PaddingEdge.allCases, id: \.self) { edge in
                handle(edge, in: rect)
            }

            if drag != nil {
                Text(model.look.canvas.autoPadding ? "Auto · \(Int(model.effectivePadding)) pt" : "\(Int(model.effectivePadding)) pt")
                    .monospacedDigit()
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .floatingGlass(in: Capsule())
                    .fixedSize()
                    .frame(width: rect.width * scale)
                    .offset(x: rect.minX * scale, y: rect.midY * scale - 16)
                    .allowsHitTesting(false)
            }
        }
    }

    private func handle(_ edge: FrameLayout.PaddingEdge, in rect: CGRect) -> some View {
        let vertical = edge == .leading || edge == .trailing
        let center: CGPoint = switch edge {
        case .top: CGPoint(x: rect.midX, y: rect.minY)
        case .bottom: CGPoint(x: rect.midX, y: rect.maxY)
        case .leading: CGPoint(x: rect.minX, y: rect.midY)
        case .trailing: CGPoint(x: rect.maxX, y: rect.midY)
        }
        let knob = vertical ? CGSize(width: 5, height: 24) : CGSize(width: 24, height: 5)
        let target = vertical ? CGSize(width: 16, height: 44) : CGSize(width: 44, height: 16)
        return Knob()
            .frame(width: knob.width, height: knob.height)
            .frame(width: target.width, height: target.height)
            .contentShape(Rectangle())
            .offset(x: center.x * scale - target.width / 2, y: center.y * scale - target.height / 2)
            .gesture(dragGesture(edge))
            .pointerStyle(pointer(edge))
            .help("Drag to change the padding")
    }

    private func dragGesture(_ edge: FrameLayout.PaddingEdge) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .global)
            .onChanged { value in
                if drag == nil {
                    // A full page's canvas grows with its padding, so keep the scale it started at.
                    drag = (model.effectivePadding, scale)
                    isAutomatic = model.look.canvas.autoPadding
                    model.beginGesture()
                }
                guard let drag else { return }
                let output = model.capture.outputSize
                let result = FrameLayout.draggedPadding(
                    from: drag.padding, edge: edge,
                    translation: CGSize(width: value.translation.width / drag.scale, height: value.translation.height / drag.scale),
                    automatic: FrameLayout.automaticPadding(for: output),
                    limit: min(FrameLayout.maximumPadding(output: output, chrome: layout.chromeHeight), 400),
                    // 6 screen points of pull, whatever the zoom.
                    tolerance: 6 / drag.scale
                )
                if result.isAutomatic, !isAutomatic {
                    NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                }
                isAutomatic = result.isAutomatic
                model.setPadding(result.padding)
            }
            .onEnded { _ in
                drag = nil
                model.endGesture(as: "Change Padding")
            }
    }

    private func pointer(_ edge: FrameLayout.PaddingEdge) -> PointerStyle {
        switch edge {
        case .top: .frameResize(position: .top)
        case .bottom: .frameResize(position: .bottom)
        case .leading: .frameResize(position: .leading)
        case .trailing: .frameResize(position: .trailing)
        }
    }
}
