import Foundation
import os
import SwiftUI

/// Reads one receipt into lines matched against the space's list. The production implementation sends the
/// photos to the backend (`APIReceiptRecognizer`); `FakeReceiptRecognizer` stands in until phase 9 wires networking.
protocol ReceiptRecognizer: Sendable {
    /// `pages` are 1–5 photos of the *same* receipt, top to bottom (possibly overlapping), each already prepared by
    /// `ReceiptImage` (≤ 1568 px, no metadata). One call → one receipt → one review → one trip.
    func recognize(_ pages: [Data], in space: SpaceKind) async throws -> ScannedReceipt
}

enum ReceiptScanError: Error, Equatable {
    /// No connection — keep the photo and offer Retry.
    case offline
    /// The photo isn't a readable receipt (422 `receipt_unreadable`).
    case unreadable
    /// Anything else on the server's side (5xx, 503 `scan_unavailable`).
    case unavailable

    var title: String {
        switch self {
        case .offline: "You’re offline"
        case .unreadable: "Couldn’t read this receipt"
        case .unavailable: "Couldn’t read the receipt right now"
        }
    }

    var message: String {
        switch self {
        case .offline: "The photo needs to be sent to read the receipt. Check your connection and try again."
        case .unreadable: "Try a sharper photo with the whole receipt in view, flat and in good light."
        case .unavailable: "Something went wrong on our side. Try again in a moment."
        }
    }

    /// Retrying the same photo can help; an unreadable photo needs a new one.
    var canRetry: Bool { self != .unreadable }
}

// MARK: - Backend

/// `POST /v1/spaces/{spaceID}/receipts/scan` — multipart, one `images` part per page (JPEG), in order. The response is the matched review:
/// `merchant`, `shopped_at`, `total_grosze` and `lines` shaped like `ReceiptLineMatch`.
///
/// Note: the endpoint is being built on back/feature/receipt-scan and isn't in the published spec yet; this
/// follows the existing `receipts/match` response; the repeated `images` field for 1–5 pages is an assumption too.
/// Align `request` and `Response` when the spec lands. Not wired until phase 9.
struct APIReceiptRecognizer: ReceiptRecognizer {
    var baseURL: URL
    var session: URLSession = .shared
    /// The server ID of the active Shared / Personal space.
    var spaceID: @Sendable (SpaceKind) async -> UUID?
    /// A valid access token (refreshed by the caller when needed).
    var accessToken: @Sendable () async -> String?

    func recognize(_ pages: [Data], in space: SpaceKind) async throws -> ScannedReceipt {
        guard (1...ReceiptScanFlow.maxPages).contains(pages.count) else { throw ReceiptScanError.unreadable }
        guard let id = await spaceID(space), let token = await accessToken() else { throw ReceiptScanError.unavailable }
        let request = Self.request(baseURL: baseURL, spaceID: id, token: token, pages: pages)
        let (data, response): (Data, URLResponse)
        do {
            (data, response) = try await session.data(for: request)
        } catch let error as URLError where Self.offlineCodes.contains(error.code) {
            throw ReceiptScanError.offline
        }
        switch (response as? HTTPURLResponse)?.statusCode ?? 0 {
        case 200: return try Self.decode(data)
        case 413, 415, 422: throw ReceiptScanError.unreadable
        default: throw ReceiptScanError.unavailable
        }
    }

    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
        .cannotFindHost, .dataNotAllowed, .internationalRoamingOff,
    ]

    static func request(baseURL: URL, spaceID: UUID, token: String, pages: [Data],
                        boundary: String = UUID().uuidString) -> URLRequest {
        let url = baseURL.appending(path: "v1/spaces/\(spaceID.uuidString.lowercased())/receipts/scan")
        var request = URLRequest(url: url, timeoutInterval: 60) // reading takes a few seconds
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
        var body = Data()
        for (i, page) in pages.enumerated() {
            body.append(Data("--\(boundary)\r\n".utf8))
            body.append(Data("Content-Disposition: form-data; name=\"images\"; filename=\"page-\(i + 1).jpg\"\r\n".utf8))
            body.append(Data("Content-Type: image/jpeg\r\n\r\n".utf8))
            body.append(page)
            body.append(Data("\r\n".utf8))
        }
        body.append(Data("--\(boundary)--\r\n".utf8))
        request.httpBody = body
        return request
    }

    struct Response: Decodable {
        struct Candidate: Decodable {
            var itemId: UUID
            var purchaseId: UUID?
            var name: String
        }

        struct Line: Decodable {
            var index: Int
            var name: String
            var qty: String?
            var priceGrosze: Int?
            var status: ReceiptLineStatus
            var match: Candidate?
            var didYouMean: Candidate?
        }

        var merchant: String?
        var shoppedAt: Date?
        var totalGrosze: Int?
        var lines: [Line]
    }

    static func decode(_ data: Data) throws -> ScannedReceipt {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .iso8601
        let r = try decoder.decode(Response.self, from: data)
        func candidate(_ c: Response.Candidate?) -> ReceiptCandidate? {
            c.map { ReceiptCandidate(itemID: $0.itemId, name: $0.name, alreadyBought: $0.purchaseId != nil) }
        }
        return ScannedReceipt(
            merchant: r.merchant,
            shoppedAt: r.shoppedAt,
            total: r.totalGrosze.map(Money.decimal(grosze:)),
            lines: r.lines.sorted { $0.index < $1.index }.map {
                .init(name: $0.name, qty: $0.qty, price: $0.priceGrosze.map(Money.decimal(grosze:)),
                      status: $0.status, match: candidate($0.match), didYouMean: candidate($0.didYouMean))
            }
        )
    }
}

// MARK: - Stand-in

/// Answers like the backend would for a known receipt: each fixture line names the list item the server would
/// match it to (resolved against the space's current candidates — no matching rules here). Several seconds of
/// "reading", like the real call. `offline` and `unreadable` fixtures throw those errors. With several fixtures,
/// each call answers with the next one (a queue of different receipts), cycling.
struct FakeReceiptRecognizer: ReceiptRecognizer {
    var fixtures: [ReceiptFixture]
    var delay: Duration = .milliseconds(2500)
    var candidates: @MainActor @Sendable (SpaceKind) -> [ReceiptCandidate]
    var now: @Sendable () -> Date = { .now }
    private let calls = OSAllocatedUnfairLock(initialState: 0)

    init(fixtures: [ReceiptFixture], delay: Duration = .milliseconds(2500),
         candidates: @escaping @MainActor @Sendable (SpaceKind) -> [ReceiptCandidate],
         now: @escaping @Sendable () -> Date = { .now }) {
        self.fixtures = fixtures.isEmpty ? [.corner] : fixtures
        self.delay = delay
        self.candidates = candidates
        self.now = now
    }

    init(fixture: ReceiptFixture, delay: Duration = .milliseconds(2500),
         candidates: @escaping @MainActor @Sendable (SpaceKind) -> [ReceiptCandidate],
         now: @escaping @Sendable () -> Date = { .now }) {
        self.init(fixtures: [fixture], delay: delay, candidates: candidates, now: now)
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
        return ScannedReceipt(
            merchant: fixture.merchant,
            shoppedAt: now().addingTimeInterval(-fixture.minutesAgo * 60),
            total: fixture.total,
            lines: fixture.lines.map { line in
                let match = find(line.matches)
                let suggestion = find(line.didYouMean)
                let status: ReceiptLineStatus = match != nil ? .matched : (suggestion != nil || line.unreadable ? .unclear : .extra)
                return .init(name: line.name, qty: line.qty, price: line.price, status: status,
                             match: match, didYouMean: match == nil ? suggestion : nil)
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
