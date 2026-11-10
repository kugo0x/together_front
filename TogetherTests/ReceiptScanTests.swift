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
        #expect(max(width, height) <= ReceiptImage.maxLongSide)
        #expect(width * height <= ReceiptImage.maxPixels, "12 MP shrinks to the backend's 3.75 MP")
        #expect(width * height > 3_600_000, "but no further")
        #expect(height > width, "portrait kept")
        let source = try #require(CGImageSourceCreateWithData(jpeg as CFData, nil))
        #expect(CGImageSourceGetType(source) as String? == UTType.jpeg.identifier)
    }

    /// A long, narrow receipt keeps 2576 px on its long side, so it stays readable across (> 400 px wide).
    @Test func longReceiptKeepsItsWidth() throws {
        let p = try properties(ReceiptImage.jpeg(from: cameraPhoto(width: 1200, height: 4800)))
        #expect(p[kCGImagePropertyPixelHeight] as? Int == 2576)
        #expect(try #require(p[kCGImagePropertyPixelWidth] as? Int) >= 640)
    }

    /// Even a photo that compresses badly (noise) stays under the backend's per-photo limit, so 5 fit in 20 MB.
    @Test func photosStayUnderTheUploadLimits() throws {
        let width = 1456, height = 2576
        var bytes = [UInt8](repeating: 0, count: width * height * 4)
        var seed: UInt32 = 42
        for i in bytes.indices { seed = seed &* 1_664_525 &+ 1_013_904_223; bytes[i] = UInt8(truncatingIfNeeded: seed >> 24) }
        let context = try #require(CGContext(data: &bytes, width: width, height: height, bitsPerComponent: 8,
                                             bytesPerRow: width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                             bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue))
        let noise = try #require(context.makeImage())
        #expect(try ReceiptImage.encode(noise, quality: 0.8).count > ReceiptImage.maxBytes, "the first quality is too big")
        let jpeg = try ReceiptImage.jpeg(from: noise)
        #expect(jpeg.count <= ReceiptImage.maxBytes)
        #expect(ReceiptImage.maxBytes * ReceiptScanFlow.maxPages < 20 << 20, "5 photos fit the 20 MB scan limit")
        #expect(ReceiptImage.maxBytes < 8 << 20)
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
        #expect(request.timeoutInterval >= 100, "a scan takes 10–40 s")
        let body = try #require(request.httpBody)
        let text = String(decoding: body, as: UTF8.self)
        #expect(text.hasPrefix("--B\r\nContent-Disposition: form-data; name=\"image\"; filename=\"part-1.jpg\"\r\nContent-Type: image/jpeg\r\n\r\n"))
        #expect(text.contains("\r\n--B\r\nContent-Disposition: form-data; name=\"image\"; filename=\"part-2.jpg\"\r\n"))
        #expect(!text.contains("name=\"images\""), "the backend reads repeated `image` parts")
        #expect(text.components(separatedBy: "name=\"image\"").count == 3)
        #expect(text.hasSuffix("\r\n--B--\r\n"))
        let first = try #require(body.range(of: top)), second = try #require(body.range(of: bottom))
        #expect(first.lowerBound < second.lowerBound, "top of the receipt first")
    }

    @Test func onlyOneToFivePagesAreSent() async {
        let api = APIReceiptRecognizer(baseURL: URL(string: "https://api.together.app")!, spaceID: { _ in nil },
                                       accessToken: { nil })
        await #expect(throws: ReceiptScanError.unreadable) { try await api.recognize([], in: .shared) }
        await #expect(throws: ReceiptScanError.unreadable) {
            try await api.recognize(Array(repeating: Data(), count: 6), in: .shared)
        }
    }

    /// A `ReceiptScan` as back/api/openapi.yaml 0.8.0 describes it: a weighed line, a rabat, an unsure line with
    /// "did you mean", an already-ticked match, and lines that don't add up to "SUMA PLN".
    static func sample(milk: UUID, bread: UUID, purchase: UUID) -> String {
        """
        {
          "receipt": {
            "merchant": "Biedronka",
            "purchased_on": "2026-11-07",
            "currency": "PLN",
            "total_grosze": 3605,
            "lines_total_grosze": 3505,
            "total_matches": false
          },
          "lines": [
            {"index": 1, "name": "Pomidory luz", "qty": "1.02 kg", "price_grosze": 918, "status": "extra",
             "match": null, "did_you_mean": null,
             "raw": "POMIDORY LUZ", "quantity": 1.02, "unit": "kg", "unit_price_grosze": 900,
             "line_price_grosze": 918, "discount_grosze": 0, "confidence": "high", "unclear": false},
            {"index": 0, "name": "Mleko owsiane 1 l", "qty": "2", "price_grosze": 998, "status": "matched",
             "match": {"item_id": "\(milk)", "purchase_id": null, "name": "Mleko owsiane"}, "did_you_mean": null,
             "raw": "MLEKO OWS 1L", "quantity": 2, "unit": "szt", "unit_price_grosze": 499,
             "line_price_grosze": 998, "discount_grosze": 0, "confidence": "high", "unclear": false},
            {"index": 2, "name": "Jogurt grecki 400 g", "qty": "2", "price_grosze": 658, "status": "extra",
             "match": null, "did_you_mean": null,
             "raw": "JOG.GRECKI 400G", "quantity": 2, "unit": "szt", "unit_price_grosze": 379,
             "line_price_grosze": 758, "discount_grosze": 100, "confidence": "medium", "unclear": false},
            {"index": 3, "name": "CHLB", "qty": null, "price_grosze": 931, "status": "unclear", "match": null,
             "did_you_mean": {"item_id": "\(bread)", "purchase_id": "\(purchase)", "name": "Chleb"},
             "raw": "CHLB", "quantity": null, "unit": null, "unit_price_grosze": null,
             "line_price_grosze": 931, "discount_grosze": 0, "confidence": "low", "unclear": true}
          ]
        }
        """
    }

    @Test func decodesTheSpecsScan() throws {
        let milk = UUID(), breadID = UUID(), purchase = UUID()
        let r = try APIReceiptRecognizer.decode(Data(Self.sample(milk: milk, bread: breadID, purchase: purchase).utf8))
        #expect(r.merchant == "Biedronka")
        #expect(r.purchasedOn == DateComponents(year: 2026, month: 11, day: 7))
        #expect(r.currency == "PLN")
        #expect(r.total == Decimal(string: "36.05"))
        #expect(r.linesTotal == Decimal(string: "35.05"))
        #expect(r.totalMatches == false)
        #expect(r.lines.map(\.raw) == ["MLEKO OWS 1L", "POMIDORY LUZ", "JOG.GRECKI 400G", "CHLB"], "server order by index")

        let milkLine = r.lines[0]
        #expect(milkLine.status == .matched)
        #expect(milkLine.match == ReceiptCandidate(itemID: milk, name: "Mleko owsiane"))
        #expect(milkLine.quantityText == "2 × 4,99")

        let tomatoes = r.lines[1]
        #expect(tomatoes.quantity == Decimal(string: "1.02") && tomatoes.unit == "kg")
        #expect(tomatoes.quantityText == "1,020 kg × 9,00")

        let yogurt = r.lines[2]
        #expect(yogurt.linePrice == Decimal(string: "7.58"))
        #expect(yogurt.discount == 1)
        #expect(yogurt.price == Decimal(string: "6.58"), "line − rabat")
        #expect(yogurt.confidence == .medium)

        let bread = r.lines[3]
        #expect(bread.unclear && bread.confidence == .low && bread.status == .unclear)
        #expect(bread.didYouMean == ReceiptCandidate(itemID: breadID, name: "Chleb", alreadyBought: true))
        #expect(bread.quantityText == nil)
    }

    @Test func reviewShowsRawTextRabatAndTheTotalNote() throws {
        let scanned = try APIReceiptRecognizer.decode(Data(Self.sample(milk: UUID(), bread: UUID(), purchase: UUID()).utf8))
        let now = instant(2026, 11, 9, 15, 37)
        var review = ReceiptReview(scanned: scanned, candidates: [], now: now, calendar: warsaw)
        #expect(review.date == instant(2026, 11, 7, 12), "the printed day, at noon")
        #expect(review.lines[0].detail == "MLEKO OWS 1L · 2 × 4,99")
        #expect(review.lines[2].detail == "JOG.GRECKI 400G · 2 × 3,79 · rabat −1,00")
        #expect(review.lines[3].detail == nil, "raw = name: shown once")
        #expect(review.total == Decimal(string: "36.05"))
        #expect(review.linesDontAddUp)
        // The person finds the misread price: the note goes away.
        review.setPrice(review.lines[3].id, Decimal(string: "10.31"))
        #expect(!review.linesDontAddUp)
    }

    @Test func aReceiptFromTodayUsesTheCurrentTime() throws {
        var scanned = try APIReceiptRecognizer.decode(Data(Self.sample(milk: UUID(), bread: UUID(), purchase: UUID()).utf8))
        let now = instant(2026, 11, 7, 18, 5)
        #expect(ReceiptReview(scanned: scanned, candidates: [], now: now, calendar: warsaw).date == now)
        scanned.purchasedOn = nil
        #expect(ReceiptReview(scanned: scanned, candidates: [], now: now, calendar: warsaw).date == now)
        scanned.purchasedOn = DateComponents(year: 2026, month: 12, day: 1) // misread, in the future
        #expect(ReceiptReview(scanned: scanned, candidates: [], now: now, calendar: warsaw).date == now)
    }

    @Test func errorCodesMapToTheirOwnCopy() {
        func body(_ code: String) -> Data { Data(#"{"error":{"code":"\#(code)","message":"…"}}"#.utf8) }
        typealias API = APIReceiptRecognizer
        #expect(API.error(status: 422, body: body("not_a_receipt"), retryAfter: nil) == .notAReceipt)
        #expect(API.error(status: 422, body: body("receipt_unreadable"), retryAfter: nil) == .unreadable)
        #expect(API.error(status: 422, body: body("receipt_too_long"), retryAfter: nil) == .tooLong)
        #expect(API.error(status: 422, body: body("bad_image"), retryAfter: nil) == .unreadable)
        #expect(API.error(status: 413, body: body("image_too_large"), retryAfter: nil) == .tooLarge)
        #expect(API.error(status: 429, body: body("rate_limited"), retryAfter: 3600) == .dailyLimit(retryAfter: 3600))
        #expect(API.error(status: 503, body: body("receipt_scan_unavailable"), retryAfter: 29) == .busy(retryAfter: 29))
        #expect(API.error(status: 503, body: body("receipt_scan_disabled"), retryAfter: nil) == .disabled)
        #expect(API.error(status: 503, body: Data("<html>".utf8), retryAfter: 10) == .busy(retryAfter: 10))
        #expect(API.error(status: 500, body: Data(), retryAfter: nil) == .unavailable)

        let all: [ReceiptScanError] = [.offline, .notAReceipt, .unreadable, .tooLong, .tooLarge, .busy(retryAfter: nil),
                                       .dailyLimit(retryAfter: nil), .disabled, .unavailable]
        #expect(Set(all.map(\.title)).count == all.count, "each error has its own title")
        #expect(ReceiptScanError.busy(retryAfter: 29).canRetry && ReceiptScanError.offline.canRetry)
        #expect(!ReceiptScanError.tooLong.canRetry && !ReceiptScanError.notAReceipt.canRetry)
        #expect(!ReceiptScanError.dailyLimit(retryAfter: nil).canUseAnotherPhoto && !ReceiptScanError.disabled.canUseAnotherPhoto)
        #expect(ReceiptScanError.busy(retryAfter: 29).message == "Try again in a moment.")
        #expect(ReceiptScanError.busy(retryAfter: 150).message == "Try again in about 3 minutes.")
        #expect(ReceiptScanError.dailyLimit(retryAfter: 6 * 3600).message.contains("in about 6 hours"))
        #expect(ReceiptScanError.dailyLimit(retryAfter: nil).message.contains("tomorrow"))
    }

    @Test func offlineErrorsAreRecognised() {
        #expect(APIReceiptRecognizer.offlineCodes.contains(.notConnectedToInternet))
        #expect(APIReceiptRecognizer.offlineCodes.contains(.timedOut))
    }

    @Test func standInThrowsTheFixturesError() async {
        for (fixture, error) in [(ReceiptFixture.offline, ReceiptScanError.offline), (.unreadable, .unreadable),
                                 (.notReceipt, .notAReceipt), (.tooLong, .tooLong), (.limit, .dailyLimit(retryAfter: 6 * 3600))] {
            await #expect(throws: error) {
                try await FakeReceiptRecognizer(fixture: fixture, delay: .zero, candidates: { _ in [] }).recognize([Data()], in: .shared)
            }
        }
    }

    @Test func standInAnswersInTheRealShape() async throws {
        let scanned = try await FakeReceiptRecognizer(fixture: .biedronka, delay: .zero, candidates: { _ in [] })
            .recognize([Data()], in: .shared)
        #expect(scanned.total == Decimal(string: "71.91"))
        #expect(scanned.linesTotal == Decimal(string: "71.91"))
        #expect(scanned.totalMatches == true)
        let yogurt = try #require(scanned.lines.first { $0.raw == "JOG.GRECKI 400G" })
        #expect(yogurt.name == "Jogurt grecki 400 g")
        #expect(yogurt.linePrice == Decimal(string: "7.58") && yogurt.discount == 1 && yogurt.price == Decimal(string: "6.58"))
        #expect(scanned.lines.first { $0.raw == "BANANY LUZ" }?.qty == "1.1 kg")

        let mismatch = try await FakeReceiptRecognizer(fixture: .mismatch, delay: .zero, candidates: { _ in [] })
            .recognize([Data()], in: .shared)
        #expect(mismatch.totalMatches == false)
    }

    @Test func standInOnlyMatchesItemsThatAreOnTheList() async throws {
        // With an empty list, nothing can be matched — "matches" lines become extras, suggestions disappear.
        let scanned = try await FakeReceiptRecognizer(fixture: .corner, delay: .zero, candidates: { _ in [] })
            .recognize([Data()], in: .shared)
        #expect(scanned.lines.allSatisfy { $0.status == .extra || $0.unclear })
        #expect(scanned.lines.allSatisfy { $0.match == nil && $0.didYouMean == nil })
    }

    @Test func anUnsureLineIsNeverMatched() async throws {
        let oat = ReceiptCandidate(itemID: UUID(), name: "Oat milk")
        var fixture = ReceiptFixture.corner
        fixture.lines[0].unsure = true
        let scanned = try await FakeReceiptRecognizer(fixture: fixture, delay: .zero, candidates: { _ in [oat] })
            .recognize([Data()], in: .shared)
        #expect(scanned.lines[0].status == .unclear)
        #expect(scanned.lines[0].didYouMean == oat, "its item is offered instead")
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
