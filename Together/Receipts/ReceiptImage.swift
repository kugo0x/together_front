import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Prepares a receipt photo for upload: JPEG, long side at most 1568 px (what the vision model reads at full
/// detail — larger only costs upload time), and no metadata at all, so no location ever leaves the phone.
enum ReceiptImage {
    static let maxLongSide = 1568
    static let quality = 0.8

    enum Failure: Error { case unreadable }

    /// From a camera page or a decoded photo.
    static func jpeg(from image: CGImage) throws -> Data {
        let scaled = try downscale(image)
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.unreadable
        }
        // Only the compression option: no EXIF, GPS, TIFF or maker-note dictionaries are written.
        CGImageDestinationAddImage(destination, scaled, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw Failure.unreadable }
        return data as Data
    }

    /// From a file picked in Photos (HEIC, JPEG, PNG…), honouring its orientation.
    static func jpeg(from data: Data) throws -> Data {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let image = CGImageSourceCreateThumbnailAtIndex(source, 0, [
                  kCGImageSourceCreateThumbnailFromImageAlways: true,
                  kCGImageSourceCreateThumbnailWithTransform: true, // apply EXIF orientation, then drop it
                  kCGImageSourceThumbnailMaxPixelSize: maxLongSide,
              ] as CFDictionary) else { throw Failure.unreadable }
        return try jpeg(from: image)
    }

    /// A long receipt scanned as several pages becomes one tall image, top to bottom.
    static func stitch(_ pages: [CGImage]) throws -> CGImage {
        guard pages.count > 1 else {
            guard let page = pages.first else { throw Failure.unreadable }
            return page
        }
        let width = pages.map(\.width).max() ?? 0
        let height = pages.reduce(0) { $0 + $1.height }
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure.unreadable }
        context.setFillColor(CGColor(gray: 1, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        var top = height
        for page in pages {
            top -= page.height
            context.draw(page, in: CGRect(x: 0, y: top, width: page.width, height: page.height))
        }
        guard let image = context.makeImage() else { throw Failure.unreadable }
        return image
    }

    private static func downscale(_ image: CGImage) throws -> CGImage {
        let long = max(image.width, image.height)
        guard long > maxLongSide else { return image }
        let scale = Double(maxLongSide) / Double(long)
        let width = Int((Double(image.width) * scale).rounded()), height = Int((Double(image.height) * scale).rounded())
        guard let context = CGContext(
            data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
            space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
        ) else { throw Failure.unreadable }
        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))
        guard let scaled = context.makeImage() else { throw Failure.unreadable }
        return scaled
    }
}
