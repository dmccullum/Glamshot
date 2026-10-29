import AppKit
import SwiftUI

/// The About window's signature, in the icon's place: the app icon, and a click on it (or
/// anywhere around it) sets off a burst of paparazzi flashes around the pointer while the
/// icon lights up.
///
/// The icon invites the click on its own (F7): 0.6 s after the window opens it fires a small
/// burst from the flash window in its art, and until the first click the flash window glints
/// every few seconds while the window is key. Hovering lights the icon a little and shows the
/// pointing hand. Under Reduce Motion there are no glints, and every flash only fades: a
/// click gives one.
struct FlashSignature: View {
    @State private var flashes: [Flash] = []
    @State private var lit = false
    @State private var hovering = false
    /// Set by the first click; stops the demo and the glints.
    @State private var used = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    /// False while the About window isn't key, which pauses the glints.
    @Environment(\.appearsActive) private var appearsActive

    /// Exactly the icon's height, so the icon and name sit where `AboutView` puts them for
    /// apps that show the icon; flashes draw past the top and bottom.
    static let size = CGSize(width: 330, height: iconSize)
    static let iconSize: CGFloat = 96
    static let iconCenter = CGPoint(x: size.width / 2, y: size.height / 2)
    /// The flash window at the right end of the icon's toolbar: (703, 258) on its 1024 grid.
    static let flashWindow = CGPoint(x: iconCenter.x + (703.0 / 1024 - 0.5) * iconSize,
                                     y: iconCenter.y + (258.0 / 1024 - 0.5) * iconSize)
    private static let glintInterval = Duration.seconds(3.2)

    struct Flash: Identifiable {
        let id = UUID()
        let point: CGPoint
        let size: CGFloat
        let delay: Double
    }

    var body: some View {
        ZStack {
            // No added shadow (F7): the icon's own art carries its depth.
            Image(nsImage: NSApplication.shared.applicationIconImage)
                .resizable()
                .interpolation(.high)
                .frame(width: Self.iconSize, height: Self.iconSize)
                .brightness(lit ? 0.18 : hovering ? 0.05 : 0)
                .animation(.easeOut(duration: 0.15), value: hovering)
                .position(Self.iconCenter)
            ForEach(flashes) { flash in
                FlashView(size: flash.size, delay: flash.delay, reduceMotion: reduceMotion)
                    .position(flash.point)
            }
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .contentShape(Rectangle())
        .pointerStyle(.link)
        .onHover { hovering = $0 }
        .onTapGesture { location in
            used = true
            burst(at: location)
        }
        .task {
            try? await Task.sleep(for: .milliseconds(600))
            guard !Task.isCancelled, !used else { return }
            burst(at: Self.flashWindow, count: 3, spread: CGSize(width: 40, height: 22))
        }
        .task(id: glints) {
            guard glints else { return }
            while !Task.isCancelled {
                try? await Task.sleep(for: Self.glintInterval)
                guard !Task.isCancelled else { return }
                show([Flash(point: Self.flashWindow, size: 20, delay: 0)])
            }
        }
        .accessibilityElement()
        .accessibilityLabel("Glamshot icon")
        .accessibilityHint("Sets off camera flashes.")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction {
            used = true
            burst(at: Self.iconCenter)
        }
    }

    /// Glints while the window is key and nobody has clicked yet.
    private var glints: Bool {
        !reduceMotion && appearsActive && !used
    }

    private func burst(at point: CGPoint, count: Int = 7, spread: CGSize = CGSize(width: 90, height: 40)) {
        if reduceMotion {
            show([Flash(point: point, size: 54, delay: 0)])
        } else {
            show((0..<count).map { index in
                Flash(
                    point: CGPoint(
                        x: min(Self.size.width - 10, max(10, point.x + .random(in: -spread.width...spread.width))),
                        y: min(Self.size.height + 8, max(-24, point.y + .random(in: -spread.height...spread.height)))
                    ),
                    size: .random(in: 26...54),
                    delay: Double(index) * 0.07 + .random(in: 0...0.05)
                )
            })
        }
        withAnimation(.easeOut(duration: 0.06)) { lit = true }
        Task {
            try? await Task.sleep(for: .seconds(0.12))
            withAnimation(.easeOut(duration: 0.6)) { lit = false }
        }
    }

    /// Adds flashes and removes them once they've faded.
    private func show(_ new: [Flash]) {
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
    @Environment(\.colorScheme) private var colorScheme

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
        // White adds light over a dark window; over a light one a faint gray edge keeps it visible.
        .blendMode(colorScheme == .dark ? .plusLighter : .normal)
        .shadow(color: colorScheme == .dark ? .white : .black.opacity(0.3), radius: colorScheme == .dark ? 6 : 3)
        .scaleEffect(reduceMotion || phase > 0 ? 1 : 0.3)
        .opacity(phase == 1 ? 1 : 0)
        .task {
            try? await Task.sleep(for: .seconds(delay))
            withAnimation(.easeOut(duration: 0.06)) { phase = 1 }
            try? await Task.sleep(for: .seconds(0.08))
            withAnimation(.easeOut(duration: 0.5)) { phase = 2 }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}
