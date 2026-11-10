import CoreGraphics
import ImageIO
import UniformTypeIdentifiers

/// Prepares a receipt photo for upload: JPEG, long side at most 2576 px and 3.75 MP (what the backend reads — larger
/// only costs upload time), under the backend's size limits, and no metadata at all, so no location ever leaves the
/// phone.
enum ReceiptImage {
    /// What the backend reads (`RECEIPT_MAX_SIDE`, the models' full resolution): at 1568 px a long, narrow receipt
    /// ends up under 400 px wide and small print is lost.
    static let maxLongSide = 2576
    /// The backend's other limit (3.75 MP); bigger photos would only be shrunk there.
    static let maxPixels = 3_750_000
    /// The backend takes 8 MB per photo and 20 MB per scan; 5 photos of at most 3.8 MB each stay under both.
    static let maxBytes = 3_800_000
    /// Tried in order until the photo fits `maxBytes` (a receipt is well under it at the first).
    static let qualities = [0.8, 0.7, 0.6, 0.5, 0.4]

    enum Failure: Error { case unreadable }

    /// From a camera page or a decoded photo.
    static func jpeg(from image: CGImage) throws -> Data {
        let scaled = try downscale(image)
        var smallest = Data()
        for quality in qualities {
            let data = try encode(scaled, quality: quality)
            if data.count <= maxBytes { return data }
            smallest = data
        }
        return smallest
    }

    static func encode(_ image: CGImage, quality: Double) throws -> Data {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil) else {
            throw Failure.unreadable
        }
        // Only the compression option: no EXIF, GPS, TIFF or maker-note dictionaries are written.
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
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

    private static func downscale(_ image: CGImage) throws -> CGImage {
        let long = max(image.width, image.height)
        let scale = min(Double(maxLongSide) / Double(long),
                        (Double(maxPixels) / Double(image.width * image.height)).squareRoot())
        guard scale < 1 else { return image }
        let width = max(1, Int(Double(image.width) * scale)), height = max(1, Int(Double(image.height) * scale))
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
