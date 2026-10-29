import CoreGraphics

/// Draws image tiles into one sRGB image, top to bottom.
enum Stitcher {
    /// - Parameter tiles: Each tile and its top edge in pixels, measured from the top. A tile
    ///   narrower or wider than `width` is scaled to fit it.
    static func stitch(_ tiles: [(image: CGImage, y: Int)], width: Int, height: Int) throws -> CGImage {
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
              ) else { throw CaptureError.imageTooLarge }
        context.interpolationQuality = .high
        for tile in tiles {
            // Core Graphics counts y up from the bottom.
            let tileHeight = (Double(tile.image.height) * Double(width) / Double(tile.image.width)).rounded()
            let rect = CGRect(x: 0, y: Double(height - tile.y) - tileHeight, width: Double(width), height: tileHeight)
            context.draw(tile.image, in: rect)
        }
        guard let image = context.makeImage() else { throw CaptureError.imageTooLarge }
        return image
    }
}
