import AppKit
import QuickLook
import SwiftUI
import UniformTypeIdentifiers

/// This session's saved and copied shots, newest first. Each one drags out as a file.
struct ShotsTray: View {
    let model: ShootModel
    @State private var quickLookURL: URL?

    var body: some View {
        ScrollView(.horizontal) {
            HStack(spacing: 10) {
                ForEach(model.shots) { shot in
                    Image(decorative: shot.image, scale: 1)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(height: 64)
                        .frame(maxWidth: 120)
                        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
                        .overlay(RoundedRectangle(cornerRadius: 6, style: .continuous).strokeBorder(.separator))
                        .help(shot.file?.lastPathComponent ?? shot.name)
                        .onDrag { provider(for: shot) }
                        .contextMenu { menu(for: shot) }
                        .accessibilityLabel(shot.file?.lastPathComponent ?? shot.name)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
        }
        .frame(height: 84)
        .background(.bar)
        .quickLookPreview($quickLookURL)
    }

    @ViewBuilder private func menu(for shot: Shot) -> some View {
        Button("Quick Look") { quickLookURL = fileURL(for: shot) }
        Button("Show in Finder") {
            if let file = shot.file { NSWorkspace.shared.activateFileViewerSelecting([file]) }
        }
        .disabled(shot.file == nil)
        Divider()
        Button("Copy Image") {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.writeObjects([NSImage(cgImage: shot.image, size: shot.pointSize)])
        }
        Divider()
        Button("Remove from Tray") { model.deleteShot(shot) }
    }

    /// The saved file, or a temporary PNG for a copied shot.
    private func fileURL(for shot: Shot) -> URL? {
        if let file = shot.file, FileManager.default.fileExists(atPath: file.path) { return file }
        let url = FileManager.default.temporaryDirectory.appending(path: shot.id.uuidString).appending(path: shot.name + ".png")
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? RenderedShot(image: shot.image, scale: 1, wasCut: false).write(to: url, format: .png)
        return url
    }

    private func provider(for shot: Shot) -> NSItemProvider {
        guard let url = fileURL(for: shot), let provider = NSItemProvider(contentsOf: url) else { return NSItemProvider() }
        provider.suggestedName = url.lastPathComponent
        return provider
    }
}
