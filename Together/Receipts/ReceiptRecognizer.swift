import Foundation
import os
import SwiftUI

/// Reads one receipt into lines matched against the space's list. The production implementation sends the
/// photos to the backend (`APIReceiptRecognizer`); `FakeReceiptRecognizer` stands in until phase 9 wires networking.
protocol ReceiptRecognizer: Sendable {
    /// `pages` are 1–5 photos of the *same* receipt, top to bottom (possibly overlapping), each already prepared by
    /// `ReceiptImage`. One call → one receipt → one review → one trip.
    func recognize(_ pages: [Data], in space: SpaceKind) async throws -> ScannedReceipt
}

/// Why a scan didn't produce a review — each with its own copy on the error screen (back/docs/receipt-scan.md
/// "Ошибки для клиента").
enum ReceiptScanError: Error, Equatable, Sendable {
    /// No connection — keep the photos and offer Retry.
    case offline
    /// 422 `not_a_receipt`.
    case notAReceipt
    /// 422 `receipt_unreadable` (also a photo the server couldn't open) — retake it.
    case unreadable
    /// 422 `receipt_too_long` — scan it in more parts.
    case tooLong
    /// 413 `image_too_large`.
    case tooLarge
    /// 503 `receipt_scan_unavailable` — overloaded or timed out; try again after `Retry-After` seconds.
    case busy(retryAfter: Int?)
    /// 429 `rate_limited` — 30 scans a day per person.
    case dailyLimit(retryAfter: Int?)
    /// 503 `receipt_scan_disabled` — not configured on this server.
    case disabled
    /// Anything else (5xx, an answer we can't read).
    case unavailable

    var title: String {
        switch self {
        case .offline: "You’re offline"
        case .notAReceipt: "This doesn’t look like a receipt"
        case .unreadable: "Couldn’t read this receipt"
        case .tooLong: "This receipt is too long for one go"
        case .tooLarge: "These photos are too large"
        case .busy: "Receipt reading is busy"
        case .dailyLimit: "That’s all the scans for today"
        case .disabled: "Receipt scanning is switched off"
        case .unavailable: "Couldn’t read the receipt right now"
        }
    }

    var message: String {
        switch self {
        case .offline:
            "The photo needs to be sent to read the receipt. Check your connection and try again."
        case .notAReceipt:
            "Take a photo of a shop receipt, with the whole receipt in view."
        case .unreadable:
            "Try a sharper photo with the whole receipt in view, flat and in good light."
        case .tooLong:
            "Scan it in parts: one photo per part, top to bottom, up to 5 photos."
        case .tooLarge:
            "Try fewer photos of this receipt, or take them again."
        case .busy(let seconds):
            "Try again " + Self.when(seconds, fallback: "in a moment") + "."
        case .dailyLimit(let seconds):
            "You can scan up to 30 receipts a day. Scanning opens again " + Self.when(seconds, fallback: "tomorrow")
                + " — until then, tick items by hand."
        case .disabled:
            "It isn’t available right now. You can still tick items by hand."
        case .unavailable:
            "Something went wrong on our side. Try again in a moment."
        }
    }

    /// Sending the same photos again can help.
    var canRetry: Bool {
        switch self {
        case .offline, .busy, .unavailable: true
        case .notAReceipt, .unreadable, .tooLong, .tooLarge, .dailyLimit, .disabled: false
        }
    }

    /// Other photos could work (not when scanning itself is off or used up for today).
    var canUseAnotherPhoto: Bool {
        switch self {
        case .dailyLimit, .disabled: false
        default: true
        }
    }

    /// "in about 2 minutes", "in about 6 hours"; under a minute (or unknown) → `fallback`.
    private static func when(_ seconds: Int?, fallback: String) -> String {
        guard let seconds, seconds >= 60 else { return fallback }
        if seconds < 3600 {
            let minutes = (seconds + 59) / 60
            return minutes == 1 ? "in about a minute" : "in about \(minutes) minutes"
        }
        let hours = (seconds + 1799) / 3600
        return hours == 1 ? "in about an hour" : "in about \(hours) hours"
    }
}

// MARK: - Backend

/// `POST /v1/spaces/{spaceID}/receipts/scan` (back/api/openapi.yaml 0.8.0) — multipart, one `image` part per photo,
/// top of the receipt first. The answer is the reviewed receipt (`ReceiptScan`). A scan takes 10–40 s, so the
/// timeout is 100 s. Goes through the app's `APIClient` (bearer token, refresh, request ID).
struct APIReceiptRecognizer: ReceiptRecognizer {
    let client: APIClient
    /// The server ID of the Shared / Personal space.
    var spaceID: @Sendable (SpaceKind) async -> UUID?

    func recognize(_ pages: [Data], in space: SpaceKind) async throws -> ScannedReceipt {
        guard (1...ReceiptScanFlow.maxPages).contains(pages.count) else { throw ReceiptScanError.unreadable }
        guard let id = await spaceID(space) else { throw ReceiptScanError.unavailable }
        let data: Data
        do {
            (data, _) = try await client.raw(Self.request(spaceID: id, pages: pages))
        } catch let error as APIError {
            switch error {
            case .offline: throw ReceiptScanError.offline
            case .server(let status, _, _, let retryAfter, let body):
                throw Self.error(status: status, body: body, retryAfter: retryAfter)
            case .signedOut, .badResponse: throw ReceiptScanError.unavailable
            }
        }
        do {
            return try Self.decode(data)
        } catch {
            throw ReceiptScanError.unavailable
        }
    }

    static func request(spaceID: UUID, pages: [Data], boundary: String = UUID().uuidString) -> APIRequest {
        var body = Data()
        for (i, page) in pages.enumerated() {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"image\"; filename=\"part-\(i + 1).jpg\"\r\n".utf8))
            body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
            body.append(page)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        var request = APIRequest(method: "POST", path: "v1/spaces/\(spaceID.uuidString.lowercased())/receipts/scan",
                                 body: body, contentType: "multipart/form-data; boundary=\(boundary)")
        request.timeout = 100 // a scan takes 10–40 s
        return request
    }

    /// The error body is `{"error": {"code", "message"}}`; the code picks the copy.
    static func error(status: Int, body: Data, retryAfter: Int?) -> ReceiptScanError {
        struct Body: Decodable {
            struct Inner: Decodable { var code: String }
            var error: Inner
        }
        let code = (try? JSONDecoder().decode(Body.self, from: body))?.error.code
        switch (status, code) {
        case (_, "not_a_receipt"?): return .notAReceipt
        case (_, "receipt_too_long"?): return .tooLong
        case (_, "receipt_scan_disabled"?): return .disabled
        case (_, "receipt_scan_unavailable"?): return .busy(retryAfter: retryAfter)
        case (429, _): return .dailyLimit(retryAfter: retryAfter)
        case (413, _): return .tooLarge
        case (400, _), (415, _), (422, _): return .unreadable // receipt_unreadable, bad_image, unsupported_image, …
        case (503, _): return .busy(retryAfter: retryAfter)
        default: return .unavailable
        }
    }

    struct Response: Decodable {
        struct Candidate: Decodable {
            var itemId: UUID
            var purchaseId: UUID?
            var name: String
        }

        struct Receipt: Decodable {
            var merchant: String?
            var purchasedOn: String?
            var currency: String
            var totalGrosze: Int?
            var linesTotalGrosze: Int
            var totalMatches: Bool?
        }

        struct Line: Decodable {
            var index: Int
            var name: String
            var qty: String?
            var priceGrosze: Int?
            var status: ReceiptLineStatus
            var match: Candidate?
            var didYouMean: Candidate?
            var raw: String
            var quantity: Decimal?
            var unit: String?
            var unitPriceGrosze: Int?
            var linePriceGrosze: Int?
            var discountGrosze: Int
            var confidence: ScannedReceipt.Confidence
            var unclear: Bool
        }

        var receipt: Receipt
        var lines: [Line]
    }

    static func decode(_ data: Data) throws -> ScannedReceipt {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let r = try decoder.decode(Response.self, from: data)
        func candidate(_ c: Response.Candidate?) -> ReceiptCandidate? {
            c.map { ReceiptCandidate(itemID: $0.itemId, name: $0.name, alreadyBought: $0.purchaseId != nil,
                                     purchaseID: $0.purchaseId) }
        }
        func money(_ grosze: Int?) -> Decimal? { grosze.map(Money.decimal(grosze:)) }
        return ScannedReceipt(
            merchant: r.receipt.merchant,
            purchasedOn: r.receipt.purchasedOn.flatMap(day),
            currency: r.receipt.currency,
            total: money(r.receipt.totalGrosze),
            linesTotal: Money.decimal(grosze: r.receipt.linesTotalGrosze),
            totalMatches: r.receipt.totalMatches,
            lines: r.lines.sorted { $0.index < $1.index }.map {
                .init(raw: $0.raw, name: $0.name, qty: $0.qty, quantity: $0.quantity, unit: $0.unit,
                      unitPrice: money($0.unitPriceGrosze), linePrice: money($0.linePriceGrosze),
                      discount: Money.decimal(grosze: $0.discountGrosze), price: money($0.priceGrosze),
                      status: $0.status, confidence: $0.confidence, unclear: $0.unclear,
                      match: candidate($0.match), didYouMean: candidate($0.didYouMean))
            }
        )
    }

    /// "2026-11-07" → year/month/day.
    private static func day(_ text: String) -> DateComponents? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return DateComponents(year: parts[0], month: parts[1], day: parts[2])
    }
}

// MARK: - Stand-in

/// Answers like the backend would for a known receipt: each fixture line names the list item the server would
/// match it to (resolved against the space's current candidates — no matching rules here; an unsure line is never
/// matched, its item comes back as "Did you mean"). Several seconds of "reading", like the real call. Error
/// fixtures throw their error. With several fixtures, each call answers with the next one (a queue), cycling.
struct FakeReceiptRecognizer: ReceiptRecognizer {
    var fixtures: [ReceiptFixture]
    var delay: Duration = .milliseconds(2500)
    var candidates: @MainActor @Sendable (SpaceKind) -> [ReceiptCandidate]
    var now: @Sendable () -> Date = { .now }
    var calendar = Calendar.current
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    init(fixtures: [ReceiptFixture], delay: Duration = .milliseconds(2500),
         candidates: @escaping @MainActor @Sendable (SpaceKind) -> [ReceiptCandidate],
         now: @escaping @Sendable () -> Date = { .now }, calendar: Calendar = .current) {
        self.fixtures = fixtures.isEmpty ? [.corner] : fixtures
        self.delay = delay
        self.candidates = candidates
        self.now = now
        self.calendar = calendar
    }

    init(fixture: ReceiptFixture, delay: Duration = .milliseconds(2500),
         candidates: @escaping @MainActor @Sendable (SpaceKind) -> [ReceiptCandidate],
         now: @escaping @Sendable () -> Date = { .now }, calendar: Calendar = .current) {
        self.init(fixtures: [fixture], delay: delay, candidates: candidates, now: now, calendar: calendar)
    }

    /// How many receipts were sent (pages of one receipt count once).
    var callCount: Int { calls.withLock { $0 } }

    func recognize(_ pages: [Data], in space: SpaceKind) async throws -> ScannedReceipt {
        guard (1...ReceiptScanFlow.maxPages).contains(pages.count) else { throw ReceiptScanError.unreadable }
        let fixture = calls.withLock { n in
            defer { n += 1 }
            return fixtures[n % fixtures.count]
        }
        try await Task.sleep(for: delay)
        if let error = fixture.error { throw error }
        let available = await candidates(space)
        func find(_ name: String?) -> ReceiptCandidate? {
            name.flatMap { n in available.first { $0.name.localizedCaseInsensitiveCompare(n) == .orderedSame } }
        }
        let linesTotal = fixture.linesTotal
        return ScannedReceipt(
            merchant: fixture.merchant,
            purchasedOn: fixture.purchasedOn ?? calendar.dateComponents([.year, .month, .day], from: now()),
            total: fixture.total,
            linesTotal: linesTotal,
            totalMatches: fixture.total.map { $0 == linesTotal },
            lines: fixture.lines.map { line in
                let unclear = line.unsure || line.confidence == .low
                let match = unclear ? nil : find(line.matches)
                let suggestion = unclear ? find(line.didYouMean ?? line.matches) : nil
                let status: ReceiptLineStatus = match != nil ? .matched : (unclear ? .unclear : .extra)
                let qty: String? = line.quantity.flatMap { q in
                    let piece = line.unit == nil || line.unit == "szt" || line.unit == "opak"
                    return piece && q == 1 ? nil : "\(q)" + (piece ? "" : " " + (line.unit ?? ""))
                }
                return .init(raw: line.raw, name: line.name, qty: qty, quantity: line.quantity, unit: line.unit,
                             unitPrice: line.unitPrice, linePrice: line.linePrice, discount: line.discount,
                             price: line.price, status: status, confidence: line.confidence, unclear: unclear,
                             match: match, didYouMean: suggestion)
            }
        )
    }
}

private struct ReceiptRecognizerKey: EnvironmentKey {
    static let defaultValue: ReceiptRecognizer = FakeReceiptRecognizer(fixture: .corner) { _ in [] }
}

extension EnvironmentValues {
    var receiptRecognizer: ReceiptRecognizer {
        get { self[ReceiptRecognizerKey.self] }
        set { self[ReceiptRecognizerKey.self] = newValue }
    }

    /// UI tests only: start the scan sheet with blank photos instead of the camera / Photos.
    var receiptTestInput: ReceiptTestInput? {
        get { self[ReceiptTestInputKey.self] }
        set { self[ReceiptTestInputKey.self] = newValue }
    }
}

/// `-receiptPhotos N` (pages of one receipt, or the grouping question when N > 1) and `-receiptSeparate YES|NO`
/// (answer it). See RootView.
enum ReceiptTestInput: Equatable, Sendable {
    case photos(Int, separate: Bool?)
}

private struct ReceiptTestInputKey: EnvironmentKey {
    static let defaultValue: ReceiptTestInput? = nil
}
