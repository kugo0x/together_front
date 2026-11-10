import Foundation
import ImageIO
import Testing
import UIKit
import UniformTypeIdentifiers
@testable import Together

/// The upload side of "Scan receipt": image preparation and the `/receipts/scan` call's shape.
struct ReceiptImageTests {
    /// A JPEG with GPS, EXIF and an orientation, like one straight from the camera roll.
    func cameraPhoto(width: Int, height: Int, orientation: Int = 1) throws -> Data {
        let context = try #require(CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                             space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        context.setFillColor(CGColor(gray: 0.9, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let image = try #require(context.makeImage())
        let data = NSMutableData()
        let destination = try #require(CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil))
        CGImageDestinationAddImage(destination, image, [
            kCGImagePropertyOrientation: orientation,
            kCGImagePropertyGPSDictionary: [kCGImagePropertyGPSLatitude: 52.2297, kCGImagePropertyGPSLatitudeRef: "N",
                                            kCGImagePropertyGPSLongitude: 21.0122, kCGImagePropertyGPSLongitudeRef: "E"],
            kCGImagePropertyExifDictionary: [kCGImagePropertyExifUserComment: "Alex's iPhone"],
        ] as CFDictionary)
        #expect(CGImageDestinationFinalize(destination))
        return data as Data
    }

    func properties(_ jpeg: Data) throws -> [CFString: Any] {
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        return (CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]) ?? [:]
    }

    @Test func fixtureReallyHasLocation() throws {
        #expect(try properties(cameraPhoto(width: 100, height: 200))[kCGImagePropertyGPSDictionary] != nil)
    }

    @Test func photoIsResizedReencodedAndStripped() throws {
        let jpeg = try ReceiptImage.jpeg(from: cameraPhoto(width: 3024, height: 4032))
        let p = try properties(jpeg)
        #expect(p[kCGImagePropertyGPSDictionary] == nil, "no location")
        #expect((p[kCGImagePropertyExifDictionary] as? [CFString: Any])?[kCGImagePropertyExifUserComment] == nil)
        let width = try #require(p[kCGImagePropertyPixelWidth] as? Int)
        let height = try #require(p[kCGImagePropertyPixelHeight] as? Int)
        #expect(max(width, height) == ReceiptImage.maxLongSide)
        #expect(height > width, "portrait kept")
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    @Test func orientationIsAppliedThenDropped() throws {
        // Stored landscape with "rotate 90°" — the receipt is really portrait.
        let p = try properties(ReceiptImage.jpeg(from: cameraPhoto(width: 2000, height: 1000, orientation: 6)))
        #expect(try #require(p[kCGImagePropertyPixelHeight] as? Int) > (p[kCGImagePropertyPixelWidth] as? Int ?? 0))
        #expect((p[kCGImagePropertyOrientation] as? Int ?? 1) == 1)
    }

    @Test func smallPhotosAreNotUpscaled() throws {
        let p = try properties(ReceiptImage.jpeg(from: cameraPhoto(width: 600, height: 900)))
        #expect(p[kCGImagePropertyPixelHeight] as? Int == 900)
    }

    @Test func pagesAreStitchedTopToBottom() throws {
        func page(_ height: Int) throws -> CGImage {
            let c = try #require(CGContext(data: nil, width: 800, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                                           space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                           bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
            return try #require(c.makeImage())
        }
        let stitched = try ReceiptImage.stitch([page(1200), page(900)])
        #expect(stitched.width == 800 && stitched.height == 2100)
        let p = try properties(ReceiptImage.jpeg(from: stitched))
        #expect(p[kCGImagePropertyPixelHeight] as? Int == ReceiptImage.maxLongSide)
    }
}

struct ReceiptAPITests {
    let space = UUID(uuidString: "6C8D3D7E-0000-4000-8000-0000000000AA")!

    @Test func requestShape() throws {
        let top = Data([0xFF, 0xD8, 0x01, 0xFF, 0xD9]), bottom = Data([0xFF, 0xD8, 0x02, 0xFF, 0xD9])
        let request = APIReceiptRecognizer.request(baseURL: URL(string: "https://api.together.app")!, spaceID: space,
                                                   token: "tok", pages: [top, bottom], boundary: "B")
        #expect(request.httpMethod == "POST")
        #expect(request.url?.absoluteString == "https://api.together.app/v1/spaces/6c8d3d7e-0000-4000-8000-0000000000aa/receipts/scan")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer tok")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "multipart/form-data; boundary=B")
        let body = try #require(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"images\"; filename=\"page-1.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        #expect(text.contains("\r\n--B\r\nContent-Disposition: form-data; name=\"images\"; filename=\"page-2.jpg\"\r\n"))
        #expect(text.hasSuffix("\r\n--B--\r\n"))
        let first = try #require(body.range(of: top)), second = try #require(body.range(of: bottom))
        #expect(first.lowerBound < second.lowerBound, "pages in order, top to bottom")
    }

    @Test func onlyOneToFivePagesAreSent() async {
        let api = APIReceiptRecognizer(baseURL: URL(string: "https://api.together.app")!, spaceID: { _ in nil },
                                       accessToken: { nil })
        await #expect(throws: ReceiptScanError.unreadable) { try await api.recognize([], in: .shared) }
        await #expect(throws: ReceiptScanError.unreadable) {
            try await api.recognize(Array(repeating: Data(), count: 6), in: .shared)
        }
    }

    @Test func decodesTheMatchedReview() throws {
        let milk = UUID(), bread = UUID(), purchase = UUID()
        let json = """
        {
          "merchant": "Biedronka",
          "shopped_at": "2026-11-07T17:42:00Z",
          "total_grosze": 7191,
          "lines": [
            {"index": 1, "name": "CZEKOLADA GORZKA", "qty": null, "price_grosze": 799, "status": "extra", "match": null, "did_you_mean": null},
            {"index": 0, "name": "MLEKO OWSIANE 1L", "qty": "2 × 4,99", "price_grosze": 998, "status": "matched",
             "match": {"item_id": "\(milk)", "purchase_id": null, "name": "Mleko owsiane"}, "did_you_mean": null},
            {"index": 2, "name": "CHLB", "qty": null, "price_grosze": null, "status": "unclear", "match": null,
             "did_you_mean": {"item_id": "\(bread)", "purchase_id": "\(purchase)", "name": "Chleb"}}
          ]
        }
        """
        let r = try APIReceiptRecognizer.decode(Data(json.utf8))
        #expect(r.merchant == "Biedronka")
        #expect(r.shoppedAt == ISO8601DateFormatter().date(from: "2026-11-07T17:42:00Z"))
        #expect(r.total == Decimal(string: "71.91"))
        #expect(r.lines.map(\.name) == ["MLEKO OWSIANE 1L", "CZEKOLADA GORZKA", "CHLB"], "server order by index")
        #expect(r.lines[0].status == .matched)
        #expect(r.lines[0].match == ReceiptCandidate(itemID: milk, name: "Mleko owsiane"))
        #expect(r.lines[0].price == Decimal(string: "9.98"))
        #expect(r.lines[2].price == nil)
        #expect(r.lines[2].didYouMean == ReceiptCandidate(itemID: bread, name: "Chleb", alreadyBought: true))
    }

    @Test func offlineErrorsAreRecognised() {
        #expect(APIReceiptRecognizer.offlineCodes.contains(.notConnectedToInternet))
        #expect(APIReceiptRecognizer.offlineCodes.contains(.timedOut))
        #expect(ReceiptScanError.offline.canRetry)
        #expect(!ReceiptScanError.unreadable.canRetry)
    }

    @Test func standInThrowsTheFixturesError() async {
        await #expect(throws: ReceiptScanError.offline) {
            try await FakeReceiptRecognizer(fixture: .offline, delay: .zero, candidates: { _ in [] }).recognize([Data()], in: .shared)
        }
        await #expect(throws: ReceiptScanError.unreadable) {
            try await FakeReceiptRecognizer(fixture: .unreadable, delay: .zero, candidates: { _ in [] }).recognize([Data()], in: .shared)
        }
    }

    @Test func standInOnlyMatchesItemsThatAreOnTheList() async throws {
        // With an empty list, nothing can be matched — "matches" lines become extras, suggestions disappear.
        let scanned = try await FakeReceiptRecognizer(fixture: .corner, delay: .zero, candidates: { _ in [] })
            .recognize([Data()], in: .shared)
        #expect(scanned.lines.allSatisfy { $0.status == .extra })
    }

    @Test func standInAnswersAQueueWithTheNextFixture() async throws {
        let fake = FakeReceiptRecognizer(fixtures: [.corner, .biedronka], delay: .zero, candidates: { _ in [] })
        let a = try await fake.recognize([Data(), Data()], in: .shared) // two pages, one receipt
        let b = try await fake.recognize([Data()], in: .shared)
        let c = try await fake.recognize([Data()], in: .shared)
        #expect([a.merchant, b.merchant, c.merchant] == ["Corner Market", "Biedronka", "Corner Market"])
        #expect(fake.callCount == 3)
    }
}
