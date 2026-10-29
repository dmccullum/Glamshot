import DMKit
import GlamshotCore
import SwiftUI

/// Lets the Safari window on a desktop be moved by its toolbar and resized by its edges and
/// corners, like a real window. The page itself stays clickable.
struct DesktopWindowHandles: View {
    let model: ShootModel
    let layout: FrameLayout
    let scale: CGFloat

    @State private var dragStart: (rect: CGRect, look: Look)?
    @State private var isDragging = false
    /// Which center guides the window is snapped to while it's moved.
    @State private var snapped = (x: false, y: false)

    private static let edge: CGFloat = 8

    var body: some View {
        let rect = layout.windowRect
        ZStack(alignment: .topLeading) {
            // The toolbar moves the window.
            Color.clear
                .contentShape(Rectangle())
                .frame(width: rect.width * scale, height: max(layout.chromeHeight, 24) * scale)
                .offset(x: rect.minX * scale, y: rect.minY * scale)
                .gesture(drag(name: "Move Window") { start, translation in
                    let moved = CGRect(origin: CGPoint(x: start.minX + translation.width, y: start.minY + translation.height), size: start.size)
                    // 8 screen points of pull, whatever the zoom.
                    let result = FrameLayout.snapToCenter(moved, in: FrameLayout.desktopArea(output: layout.canvasSize),
                                                          tolerance: 8 / scale)
                    if (result.x && !snapped.x) || (result.y && !snapped.y) {
                        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
                    }
                    snapped = (result.x, result.y)
                    return result.rect
                })
                .pointerStyle(.grabIdle)

            ForEach(Handle.allCases, id: \.self) { handle in
                let frame = handle.frame(in: rect, edge: Self.edge / scale)
                Color.clear
                    .contentShape(Rectangle())
                    .frame(width: frame.width * scale, height: frame.height * scale)
                    .offset(x: frame.minX * scale, y: frame.minY * scale)
                    .gesture(drag(name: "Resize Window") { start, translation in handle.resize(start, by: translation) })
                    .pointerStyle(handle.pointer)
            }

            if isDragging {
                centerGuides
                Text("\(Int(rect.width)) × \(Int(rect.height))")
                    .monospacedDigit()
                    .font(.callout)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .floatingGlass(in: Capsule())
                    .fixedSize()
                    .frame(width: rect.width * scale)
                    .offset(x: rect.minX * scale, y: (rect.maxY * scale) - 40)
                    .allowsHitTesting(false)
            }
        }
    }

    private func drag(name: String, _ transform: @escaping (CGRect, CGSize) -> CGRect) -> some Gesture {
        DragGesture(minimumDistance: 2, coordinateSpace: .global)
            .onChanged { value in
                if dragStart == nil {
                    dragStart = (layout.windowRect, model.look)
                    model.beginGesture()
                    isDragging = true
                }
                guard let start = dragStart else { return }
                let translation = CGSize(width: value.translation.width / scale, height: value.translation.height / scale)
                apply(transform(start.rect, translation), startLook: start.look)
            }
            .onEnded { _ in
                dragStart = nil
                isDragging = false
                snapped = (false, false)
                model.endGesture(as: name)
            }
    }

    /// Lines through the desktop's center while the window is snapped to them.
    @ViewBuilder private var centerGuides: some View {
        let area = FrameLayout.desktopArea(output: layout.canvasSize)
        if snapped.x {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: 1, height: area.height * scale)
                .offset(x: area.midX * scale, y: area.minY * scale)
                .allowsHitTesting(false)
        }
        if snapped.y {
            Rectangle()
                .fill(Color.accentColor)
                .frame(width: area.width * scale, height: 1)
                .offset(x: area.minX * scale, y: area.midY * scale)
                .allowsHitTesting(false)
        }
    }

    /// Writes a new window rect back as shares of the desktop below the menu bar.
    private func apply(_ rect: CGRect, startLook: Look) {
        model.look.desktop = FrameLayout.desktopOptions(model.look.desktop, with: rect, output: model.capture.outputSize)
    }

    enum Handle: CaseIterable {
        case top, bottom, leading, trailing, topLeading, topTrailing, bottomLeading, bottomTrailing

        func frame(in rect: CGRect, edge: CGFloat) -> CGRect {
            let corner = edge * 2
            switch self {
            case .top: return CGRect(x: rect.minX + corner, y: rect.minY - edge, width: rect.width - corner * 2, height: edge)
            case .bottom: return CGRect(x: rect.minX + corner, y: rect.maxY, width: rect.width - corner * 2, height: edge)
            case .leading: return CGRect(x: rect.minX - edge, y: rect.minY + corner, width: edge, height: rect.height - corner * 2)
            case .trailing: return CGRect(x: rect.maxX, y: rect.minY + corner, width: edge, height: rect.height - corner * 2)
            case .topLeading: return CGRect(x: rect.minX - edge, y: rect.minY - edge, width: corner, height: corner)
            case .topTrailing: return CGRect(x: rect.maxX - edge, y: rect.minY - edge, width: corner, height: corner)
            case .bottomLeading: return CGRect(x: rect.minX - edge, y: rect.maxY - edge, width: corner, height: corner)
            case .bottomTrailing: return CGRect(x: rect.maxX - edge, y: rect.maxY - edge, width: corner, height: corner)
            }
        }

        func resize(_ start: CGRect, by t: CGSize) -> CGRect {
            var r = start
            switch self {
            case .top, .topLeading, .topTrailing: r.origin.y += t.height; r.size.height -= t.height
            case .bottom, .bottomLeading, .bottomTrailing: r.size.height += t.height
            default: break
            }
            switch self {
            case .leading, .topLeading, .bottomLeading: r.origin.x += t.width; r.size.width -= t.width
            case .trailing, .topTrailing, .bottomTrailing: r.size.width += t.width
            default: break
            }
            return r
        }

        var pointer: PointerStyle {
            switch self {
            case .top: .frameResize(position: .top)
            case .bottom: .frameResize(position: .bottom)
            case .leading: .frameResize(position: .leading)
            case .trailing: .frameResize(position: .trailing)
            case .topLeading: .frameResize(position: .topLeading)
            case .topTrailing: .frameResize(position: .topTrailing)
            case .bottomLeading: .frameResize(position: .bottomLeading)
            case .bottomTrailing: .frameResize(position: .bottomTrailing)
            }
        }
    }
}
