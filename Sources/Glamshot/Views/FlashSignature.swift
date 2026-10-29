import AppKit
import SwiftUI

/// The About window's signature: click anywhere in it and a burst of paparazzi flashes goes
/// off around the pointer. Under Reduce Motion each flash only fades.
struct FlashSignature: View {
    @State private var flashes: [Flash] = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    struct Flash: Identifiable {
        let id = UUID()
        let point: CGPoint
        let size: CGFloat
        let delay: Double
    }

    var body: some View {
        ZStack {
            Text("Click to set off the flashes")
                .font(.callout)
                .foregroundStyle(.secondary)
                .opacity(flashes.isEmpty ? 1 : 0)
            ForEach(flashes) { flash in
                FlashView(size: flash.size, delay: flash.delay, reduceMotion: reduceMotion)
                    .position(flash.point)
            }
        }
        .frame(width: 280, height: 90)
        .contentShape(Rectangle())
        .onTapGesture { location in burst(at: location) }
        .accessibilityElement()
        .accessibilityLabel("Camera flashes")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { burst(at: CGPoint(x: 140, y: 45)) }
    }

    private func burst(at point: CGPoint) {
        let new = (0..<7).map { index in
            Flash(
                point: CGPoint(x: point.x + .random(in: -90...90), y: point.y + .random(in: -36...36)),
                size: .random(in: 26...54),
                delay: Double(index) * 0.07 + .random(in: 0...0.05)
            )
        }
        flashes.append(contentsOf: new)
        Task {
            try? await Task.sleep(for: .seconds(1.4))
            flashes.removeAll { flash in new.contains { $0.id == flash.id } }
        }
    }
}

private struct FlashView: View {
    let size: CGFloat
    let delay: Double
    let reduceMotion: Bool
    @State private var phase = 0

    var body: some View {
        ZStack {
            Circle()
                .fill(RadialGradient(colors: [.white, .white.opacity(0.6), .clear], center: .center, startRadius: 0, endRadius: size / 2))
            if !reduceMotion {
                // A four-point starburst.
                ForEach(0..<2) { index in
                    Capsule()
                        .fill(.white)
                        .frame(width: size * 1.4, height: 2)
                        .rotationEffect(.degrees(Double(index) * 90 + 45))
                }
            }
        }
        .frame(width: size, height: size)
        .blendMode(.plusLighter)
        .shadow(color: .white, radius: 6)
        .scaleEffect(reduceMotion || phase > 0 ? 1 : 0.3)
        .opacity(phase == 1 ? 1 : 0)
        .task {
            try? await Task.sleep(for: .seconds(delay))
            withAnimation(.easeOut(duration: 0.06)) { phase = 1 }
            try? await Task.sleep(for: .seconds(0.08))
            withAnimation(.easeOut(duration: 0.5)) { phase = 2 }
        }
        .accessibilityHidden(true)
    }
}
