import Foundation
import os

/// `GET /v1/spaces/{id}/events` (Server-Sent Events). Hands each event to `onEvent` on the main actor; when the
/// connection drops it reconnects with backoff (starting at the server's `retry:`), and after every reconnect
/// `reconnected` re-fetches the space — events missed in between aren't replayed.
@MainActor
final class SpaceEventStream {
    private let client: APIClient
    private let spaceID: UUID
    private let onEvent: @MainActor (SpaceEventDTO) -> Void
    private let reconnected: @MainActor () async -> Void
    private var task: Task<Void, Never>?
    private static let log = Logger(subsystem: "app.together", category: "events")

    init(client: APIClient, spaceID: UUID,
         onEvent: @escaping @MainActor (SpaceEventDTO) -> Void,
         reconnected: @escaping @MainActor () async -> Void) {
        self.client = client
        self.spaceID = spaceID
        self.onEvent = onEvent
        self.reconnected = reconnected
    }

    func start() {
        guard task == nil else { return }
        task = Task { [weak self] in await self?.run() }
    }

    func stop() {
        task?.cancel()
        task = nil
    }

    private func run() async {
        var delay: Duration = .seconds(3)
        var connectedBefore = false
        while !Task.isCancelled {
            do {
                var request = APIRequest.get("v1/spaces/\(spaceID)/events")
                request.headers["Accept"] = "text/event-stream"
                let (bytes, _) = try await client.stream(request)
                if connectedBefore { await reconnected() }
                connectedBefore = true
                delay = .seconds(3)
                var parser = SSEParser()
                for try await byte in bytes {
                    guard let event = parser.feed(byte) else { continue }
                    if let retry = event.retry { delay = .milliseconds(retry) }
                    guard let data = event.data, event.name != nil else { continue }
                    do {
                        onEvent(try APICoding.decoder.decode(SpaceEventDTO.self, from: Data(data.utf8)))
                    } catch {
                        Self.log.error("event \(event.name ?? "?", privacy: .public) unreadable: \(String(describing: error), privacy: .public)")
                    }
                }
            } catch is CancellationError {
                return
            } catch APIError.signedOut {
                return
            } catch {
                Self.log.info("stream dropped: \(String(describing: error), privacy: .public)")
            }
            guard !Task.isCancelled else { return }
            try? await Task.sleep(for: delay)
            delay = min(delay * 2, .seconds(30))
        }
    }
}

/// The SSE wire format, a byte at a time: `event:`, `data:` (several are joined with newlines), `id:`, `retry:`;
/// a blank line ends an event; lines starting with `:` are comments (the server's pings).
struct SSEParser {
    struct Event: Equatable {
        var name: String?
        var data: String?
        var id: String?
        var retry: Int?
    }

    private var line: [UInt8] = []
    private var current = Event()
    private var dataLines: [String] = []
    private var lastWasCR = false

    /// Returns an event when `byte` completes one.
    mutating func feed(_ byte: UInt8) -> Event? {
        if byte == UInt8(ascii: "\n") && lastWasCR { lastWasCR = false; return nil }
        lastWasCR = byte == UInt8(ascii: "\r")
        guard byte == UInt8(ascii: "\n") || byte == UInt8(ascii: "\r") else {
            line.append(byte)
            return nil
        }
        let text = String(decoding: line, as: UTF8.self)
        line.removeAll(keepingCapacity: true)
        if text.isEmpty { return dispatch() }
        guard !text.hasPrefix(":") else { return nil }
        let field: Substring, value: Substring
        if let colon = text.firstIndex(of: ":") {
            field = text[..<colon]
            var rest = text[text.index(after: colon)...]
            if rest.first == " " { rest = rest.dropFirst() }
            value = rest
        } else {
            field = Substring(text)
            value = ""
        }
        switch field {
        case "event": current.name = String(value)
        case "data": dataLines.append(String(value))
        case "id": current.id = String(value)
        case "retry": current.retry = Int(value)
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> Event? {
        defer { current = Event(); dataLines = [] }
        if !dataLines.isEmpty { current.data = dataLines.joined(separator: "\n") }
        return current == Event() ? nil : current
    }
}
