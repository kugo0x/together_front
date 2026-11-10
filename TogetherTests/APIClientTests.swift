import Foundation
import os
import Testing
@testable import Together

/// `APIClient` and `TokenVault` against a stubbed server (no network).
@Suite(.serialized)
struct APIClientTests {
    /// Answers requests from a handler; records what was asked.
    final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var handler: ((URLRequest) throws -> (Int, [String: String], Data))?
        static let seen = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func startLoading() {
            var request = request
            if request.httpBody == nil, let stream = request.httpBodyStream {
                stream.open()
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 4096)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n <= 0 { break }
                    data.append(buffer, count: n)
                }
                request.httpBody = data
            }
            let recorded = request
            Self.seen.withLock { $0.append(recorded) }
            do {
                let (status, headers, body) = try Self.handler!(request)
                let response = HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: headers)!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: body)
                client?.urlProtocolDidFinishLoading(self)
            } catch {
                client?.urlProtocol(self, didFailWithError: error)
            }
        }
        override func stopLoading() {}
    }

    static func session() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return URLSession(configuration: config)
    }

    static let base = URL(string: "https://api.test")!
    static func error(_ code: String) -> Data { Data(#"{"error":{"code":"\#(code)","message":"Nope."}}"#.utf8) }
    static let me = Data(#"{"id":"0b0c6e0a-0000-4000-8000-00000000a1e0","email":"a@b.co","email_verified":true,"display_name":"Alex","created_at":"2026-11-09T14:37:00.123Z","providers":["email"],"time_zone":"Europe/Warsaw","quiet_hours":{"start":"22:00","end":"08:00"},"avatar":null}"#.utf8)

    static func tokens(_ access: String, _ refresh: String) -> AuthTokens {
        AuthTokens(accessToken: access, accessExpiresAt: .distantFuture, refreshToken: refresh, refreshExpiresAt: .distantFuture)
    }

    func reset() { Stub.seen.withLock { $0.removeAll() } }

    @Test func sendsRequestIDAndBearerAndDecodes() async throws {
        reset()
        Stub.handler = { _ in (200, [:], Self.me) }
        let vault = TokenVault(tokens: Self.tokens("A1", "R1"), rotate: { _ in Self.tokens("A2", "R2") }, didChange: { _ in })
        let client = APIClient(baseURL: Self.base, session: Self.session(), vault: vault)
        let me = try await client.send(.get("v1/me"), as: MeDTO.self)
        #expect(me.displayName == "Alex")
        let request = try #require(Stub.seen.withLock { $0.first })
        #expect(request.url?.absoluteString == "https://api.test/v1/me")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer A1")
        let id = try #require(request.value(forHTTPHeaderField: "X-Request-Id"))
        #expect(id.count >= 8 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" }, "a short id the server accepts")
    }

    @Test func signInGoesWithoutABearer() async throws {
        reset()
        Stub.handler = { _ in (401, [:], Self.error("invalid_credentials")) }
        let vault = TokenVault(tokens: Self.tokens("A1", "R1"), rotate: { _ in Self.tokens("A2", "R2") }, didChange: { _ in })
        let client = APIClient(baseURL: Self.base, session: Self.session(), vault: vault)
        let error = await #expect(throws: APIError.self) {
            try await client.send(.send("POST", "v1/auth/login", json: LoginBody(email: "a@b.co", password: "x"), authenticated: false))
        }
        #expect(error?.code == "invalid_credentials")
        #expect(Stub.seen.withLock { $0.first?.value(forHTTPHeaderField: "Authorization") } == nil)
        #expect(APIAuthService.authError(error!) == .invalidCredentials)
    }

    /// 401 `invalid_access_token` → one refresh → the same call again with the new token; the new pair is stored.
    @Test func expiredAccessTokenIsRefreshedOnceAndRetried() async throws {
        reset()
        Stub.handler = { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer A2"
                ? (200, [:], Self.me) : (401, [:], Self.error("invalid_access_token"))
        }
        let rotations = OSAllocatedUnfairLock(initialState: [String]())
        let stored = OSAllocatedUnfairLock(initialState: [AuthTokens?]())
        let vault = TokenVault(tokens: Self.tokens("A1", "R1"),
                               rotate: { refresh in
                                   rotations.withLock { $0.append(refresh) }
                                   try await Task.sleep(for: .milliseconds(50))
                                   return Self.tokens("A2", "R2")
                               },
                               didChange: { tokens in stored.withLock { $0.append(tokens) } })
        let client = APIClient(baseURL: Self.base, session: Self.session(), vault: vault)
        // Three calls at once: one rotation for all of them (a refresh token works once).
        async let a = client.send(.get("v1/me"), as: MeDTO.self)
        async let b = client.send(.get("v1/me"), as: MeDTO.self)
        async let c = client.send(.get("v1/me"), as: MeDTO.self)
        _ = try await (a, b, c)
        #expect(rotations.withLock { $0 } == ["R1"])
        #expect(stored.withLock { $0.compactMap { $0?.refreshToken } } == ["R2"])
        #expect(await vault.tokens?.accessToken == "A2")
    }

    /// The refresh is refused (expired, revoked, replayed): signed out, the vault emptied.
    @Test func refusedRefreshSignsOut() async throws {
        reset()
        Stub.handler = { _ in (401, [:], Self.error("invalid_access_token")) }
        let signedOut = OSAllocatedUnfairLock(initialState: false)
        let vault = TokenVault(tokens: Self.tokens("A1", "R1"),
                               rotate: { _ in throw APIError.server(status: 401, code: "refresh_token_reused", message: "",
                                                                    retryAfter: nil, body: Data()) },
                               didChange: { _ in })
        let client = APIClient(baseURL: Self.base, session: Self.session(), vault: vault) {
            signedOut.withLock { $0 = true }
        }
        await #expect(throws: APIError.signedOut) { try await client.send(.get("v1/me")) }
        #expect(signedOut.withLock { $0 })
        #expect(await vault.tokens == nil)
    }

    /// Any other 401 (`session_revoked`) signs out without trying a refresh.
    @Test func otherUnauthorizedSignsOutAtOnce() async throws {
        reset()
        Stub.handler = { _ in (401, [:], Self.error("session_revoked")) }
        let rotated = OSAllocatedUnfairLock(initialState: false)
        let vault = TokenVault(tokens: Self.tokens("A1", "R1"),
                               rotate: { _ in rotated.withLock { $0 = true }; return Self.tokens("A2", "R2") }, didChange: { _ in })
        let client = APIClient(baseURL: Self.base, session: Self.session(), vault: vault)
        await #expect(throws: APIError.signedOut) { try await client.send(.get("v1/me")) }
        #expect(!rotated.withLock { $0 })
    }

    /// Offline during a refresh keeps the session (it's not the token's fault).
    @Test func offlineRefreshKeepsTheSession() async throws {
        let vault = TokenVault(tokens: Self.tokens("A1", "R1"), rotate: { _ in throw APIError.offline }, didChange: { _ in })
        await #expect(throws: APIError.offline) { try await vault.refresh(after: "A1") }
        #expect(await vault.tokens?.refreshToken == "R1")
    }

    @Test func errorsAreTyped() async throws {
        reset()
        Stub.handler = { _ in (429, ["Retry-After": "30"], Self.error("rate_limited")) }
        let client = APIClient(baseURL: Self.base, session: Self.session(), vault: nil)
        let error = await #expect(throws: APIError.self) { try await client.send(.get("v1/me")) }
        #expect(error == .server(status: 429, code: "rate_limited", message: "Nope.", retryAfter: 30, body: Self.error("rate_limited")))
        #expect(error?.isTransient == true)

        Stub.handler = { _ in (502, [:], Data("<html>bad gateway</html>".utf8)) }
        let gateway = await #expect(throws: APIError.self) { try await client.send(.get("v1/me")) }
        #expect(gateway?.code == "http_502", "a body that isn't the API's still gets a code")

        Stub.handler = { _ in throw URLError(.notConnectedToInternet) }
        await #expect(throws: APIError.offline) { try await client.send(.get("v1/me")) }

        Stub.handler = { _ in (200, [:], Data("{}".utf8)) }
        let bad = await #expect(throws: APIError.self) { try await client.send(.get("v1/me"), as: MeDTO.self) }
        if case .badResponse = bad {} else { Issue.record("a 2xx we can't read is a bad response") }
    }

    @Test func bodiesAreSnakeCaseWithRFC3339Times() throws {
        let body = try APICoding.encoder.encode(ConfirmReceiptBody(lines: [], totalGrosze: 7840, merchant: "B",
                                                                   shoppedAt: Date(timeIntervalSince1970: 0)))
        let json = String(decoding: body, as: UTF8.self)
        #expect(json.contains("\"total_grosze\":7840"))
        #expect(json.contains("\"shopped_at\":\"1970-01-01T00:00:00Z\""))
        #expect(APICoding.parseDate("2026-11-09T14:37:00.123456Z") != nil, "Go's fractional seconds")
        #expect(APICoding.parseDate("2026-11-09T15:37:00+01:00") == APICoding.parseDate("2026-11-09T14:37:00Z"))
    }

    /// Merge patches send `null` to clear; the Personal task leaves the assignee out.
    @Test func taskPatchSendsNulls() throws {
        let shared = try JSONSerialization.jsonObject(with: APICoding.encoder.encode(EditTaskBody(
            title: "T", notes: nil, due: nil, repeat: nil, assigneeId: nil, sendsAssignee: true, reminder: nil))) as! [String: Any]
        #expect(shared["notes"] is NSNull && shared["due"] is NSNull && shared["assignee_id"] is NSNull && shared["reminder"] is NSNull)
        let personal = try JSONSerialization.jsonObject(with: APICoding.encoder.encode(EditTaskBody(
            title: "T", notes: nil, due: nil, repeat: nil, assigneeId: nil, sendsAssignee: false, reminder: nil))) as! [String: Any]
        #expect(personal["assignee_id"] == nil)
    }
}

struct SSEParserTests {
    func events(_ text: String) -> [SSEParser.Event] {
        var parser = SSEParser()
        return Array(text.utf8).compactMap { parser.feed($0) }
    }

    @Test func parsesTheServersStream() {
        let stream = "retry: 3000\n: connected\n\nevent: item.bought\nid: 1\ndata: {\"a\":1}\n\n: ping\n\nevent: x\r\ndata: one\r\ndata: two\r\n\r\n"
        let parsed = events(stream)
        #expect(parsed == [
            .init(retry: 3000),
            .init(name: "item.bought", data: "{\"a\":1}", id: "1"),
            .init(name: "x", data: "one\ntwo"),
        ])
    }

    @Test func decodesAGroceryEvent() throws {
        let json = #"{"type":"item.bought","space_id":"2b3e0864-81de-4115-b2be-3c2ae792b95f","actor_id":"0b0c6e0a-0000-4000-8000-0000000005a3","at":"2026-11-09T14:37:00Z","item":{"id":"6c8d3d7e-0000-4000-8000-0000000000aa","list_id":"6c8d3d7e-0000-4000-8000-0000000000ab","space_id":"2b3e0864-81de-4115-b2be-3c2ae792b95f","name":"Tomatoes","qty":null,"note":null,"added_by":null,"done":true,"bought_by":"0b0c6e0a-0000-4000-8000-0000000005a3","bought_at":"2026-11-09T14:37:00Z","via_receipt":false,"created_at":"2026-11-09T14:00:00Z","updated_at":"2026-11-09T14:37:00Z"}}"#
        let event = try APICoding.decoder.decode(SpaceEventDTO.self, from: Data(json.utf8))
        #expect(event.type == "item.bought")
        #expect(event.item?.name == "Tomatoes")
        #expect(event.actorId == Person.sam.id)
    }
}

/// `RemoteSync` applying the partner's events to the store.
@MainActor
struct RemoteSyncEventTests {
    @Test func partnersTickShowsAttributionAndToast() throws {
        let store = AppStore(data: .empty)
        let toasts = ToastCenter()
        let me = Person.alex
        let sync = RemoteSync(client: APIClient(baseURL: URL(string: "https://api.test")!, vault: nil), store: store,
                              toasts: toasts, me: me)
        defer { sync.stop() }
        let list = store.defaultList(for: .shared)
        let itemID = UUID()
        func event(_ type: String, actor: Person, done: Bool) throws -> SpaceEventDTO {
            let json = """
            {"type":"\(type)","space_id":"\(UUID())","actor_id":"\(actor.id)","at":"2026-11-09T14:37:00Z",
             "item":{"id":"\(itemID)","list_id":"\(list.id)","space_id":"\(UUID())","name":"Tomatoes","qty":null,"note":null,
             "added_by":null,"done":\(done),"bought_by":\(done ? "\"\(actor.id)\"" : "null"),
             "bought_at":\(done ? "\"2026-11-09T14:37:00Z\"" : "null"),"via_receipt":false,
             "created_at":"2026-11-09T14:00:00Z","updated_at":"2026-11-09T14:37:00Z"}}
            """
            return try APICoding.decoder.decode(SpaceEventDTO.self, from: Data(json.utf8))
        }
        sync.apply(try event("item.added", actor: .sam, done: false), in: .shared)
        #expect(store.toBuy(in: .shared).map(\.name) == ["Tomatoes"])
        sync.apply(try event("item.bought", actor: .sam, done: true), in: .shared)
        #expect(store.bought(in: .shared).first?.boughtBy?.id == Person.sam.id)
        #expect(toasts.current?.message == "Someone bought Tomatoes" || toasts.current?.message == "Sam bought Tomatoes")
        // My own events come back too — already applied here, so they're ignored.
        sync.apply(try event("item.unbought", actor: me, done: false), in: .shared)
        #expect(store.bought(in: .shared).count == 1)
        #expect(store.sync === sync, "changes go to the server")
    }
}
