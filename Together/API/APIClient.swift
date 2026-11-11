import Foundation
import os

/// Where the API lives: the `APIBaseURL` Info.plist key, filled from the `API_BASE_URL` build setting in
/// `project.yml` — the local stack (`make dev-up` in ../back) for Debug, the Railway service for Release.
/// `-apiBaseURL <url>` (launch argument) overrides it — the integration UI tests use it.
enum APIConfig {
    static var baseURL: URL {
        if let override = UserDefaults.standard.string(forKey: "apiBaseURL"), let url = URL(string: override) {
            return url
        }
        if let configured = Bundle.main.object(forInfoDictionaryKey: "APIBaseURL") as? String,
           let url = URL(string: configured), url.host() != nil {
            return url
        }
        return URL(string: "http://localhost:8080")!
    }

    /// Fakes instead of the API: UI tests and screenshots (`-signedIn YES`, `-signedOut YES`, `-fakeBackend YES`).
    static var usesFakes: Bool {
        let defaults = UserDefaults.standard
        return defaults.bool(forKey: "signedIn") || defaults.bool(forKey: "signedOut") || defaults.bool(forKey: "fakeBackend")
    }
}

/// What can go wrong talking to the API. Screens branch on `code` (the API's `error.code`), never on `message`.
enum APIError: Error, Equatable, Sendable {
    /// No connection (or it dropped): nothing reached the server, safe to retry.
    case offline
    /// The server answered with an error body `{"error": {"code", "message"}}`.
    case server(status: Int, code: String, message: String, retryAfter: Int?, body: Data)
    /// 401 that a refresh couldn't fix: the session is over and the user has been signed out.
    case signedOut
    /// A 2xx we couldn't read — a contract mismatch, worth reporting.
    case badResponse(String)

    var code: String? {
        if case .server(_, let code, _, _, _) = self { return code }
        return nil
    }

    var status: Int? {
        if case .server(let status, _, _, _, _) = self { return status }
        return nil
    }

    /// Worth trying again later as is: offline, rate limited, or the server's trouble.
    var isTransient: Bool {
        switch self {
        case .offline: true
        case .server(let status, _, _, _, _): status == 429 || status >= 500
        case .signedOut, .badResponse: false
        }
    }

    /// The API's user-facing copy, or ours for the client-side cases.
    var message: String {
        switch self {
        case .offline: "You’re offline. Changes will sync when you’re back."
        case .server(_, _, let message, _, _): message
        case .signedOut: "You’ve been signed out. Sign in again to continue."
        case .badResponse: "Something went wrong. Try again in a moment."
        }
    }

    static let offlineCodes: Set<URLError.Code> = [
        .notConnectedToInternet, .networkConnectionLost, .timedOut, .cannotConnectToHost,
        .cannotFindHost, .dataNotAllowed, .internationalRoamingOff, .dnsLookupFailed,
    ]
}

/// One API call. Bodies are JSON (snake_case) unless a raw body is given (avatar, receipt photos).
struct APIRequest: Sendable {
    var method: String
    var path: String
    var query: [URLQueryItem] = []
    var headers: [String: String] = [:]
    var body: Data?
    var contentType: String?
    /// Sign-in, sign-up and refresh go without a bearer token.
    var authenticated = true
    var timeout: TimeInterval = 30

    static func get(_ path: String, query: [URLQueryItem] = []) -> APIRequest {
        APIRequest(method: "GET", path: path, query: query)
    }

    static func delete(_ path: String) -> APIRequest { APIRequest(method: "DELETE", path: path) }

    static func send(_ method: String, _ path: String, json: some Encodable, authenticated: Bool = true) -> APIRequest {
        APIRequest(method: method, path: path, body: try? APICoding.encoder.encode(json),
                   contentType: "application/json", authenticated: authenticated)
    }

    static func send(_ method: String, _ path: String) -> APIRequest { APIRequest(method: method, path: path) }
}

/// The API's JSON conventions: snake_case keys, RFC 3339 times (with or without fractional seconds).
enum APICoding {
    static let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.keyEncodingStrategy = .convertToSnakeCase
        encoder.dateEncodingStrategy = .custom { date, encoder in
            var container = encoder.singleValueContainer()
            try container.encode(date.formatted(.iso8601))
        }
        return encoder
    }()

    static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        decoder.dateDecodingStrategy = .custom { decoder in
            let container = try decoder.singleValueContainer()
            let text = try container.decode(String.self)
            if let date = parseDate(text) { return date }
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an RFC 3339 time: \(text)")
        }
        return decoder
    }()

    static func parseDate(_ text: String) -> Date? {
        if let date = try? Date(text, strategy: .iso8601.year().month().day().time(includingFractionalSeconds: true).timeZone(separator: .omitted)) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}

/// Holds the session's tokens and rotates them. Every refresh token works once and replaying one revokes the
/// session, so refreshes are single-flight: concurrent 401s wait for the same rotation.
actor TokenVault {
    private(set) var tokens: AuthTokens?
    private var refreshing: Task<AuthTokens, Error>?
    /// POST /v1/auth/refresh (set by whoever owns the client).
    private let rotate: @Sendable (String) async throws -> AuthTokens
    /// The new pair, to store atomically (Keychain).
    private let didChange: @Sendable (AuthTokens?) async -> Void

    init(tokens: AuthTokens?,
         rotate: @escaping @Sendable (String) async throws -> AuthTokens,
         didChange: @escaping @Sendable (AuthTokens?) async -> Void) {
        self.tokens = tokens
        self.rotate = rotate
        self.didChange = didChange
    }

    func set(_ tokens: AuthTokens?) {
        self.tokens = tokens
    }

    /// The access token to send.
    var accessToken: String? { tokens?.accessToken }

    /// Rotates once for everyone who saw `failedToken` rejected. Returns the new access token; throws when the
    /// refresh token is no good any more (then the vault is empty).
    func refresh(after failedToken: String?) async throws -> String {
        if let tokens, tokens.accessToken != failedToken { return tokens.accessToken } // someone already rotated
        if let refreshing { return try await refreshing.value.accessToken }
        guard let refreshToken = tokens?.refreshToken else { throw APIError.signedOut }
        let task = Task { try await rotate(refreshToken) }
        refreshing = task
        defer { refreshing = nil }
        do {
            let fresh = try await task.value
            tokens = fresh
            await didChange(fresh)
            return fresh.accessToken
        } catch let error as APIError where error.isTransient {
            throw error // offline mid-refresh: keep the session, try later
        } catch {
            tokens = nil
            await didChange(nil)
            throw APIError.signedOut
        }
    }
}

/// The one HTTP client: async/await over URLSession, a request ID on every call, 401 → one refresh → retry,
/// typed errors. Logs method, path, status and request ID only — never tokens, headers or bodies.
final class APIClient: Sendable {
    let baseURL: URL
    let vault: TokenVault?
    private let session: URLSession
    private let signedOut: @Sendable () async -> Void
    private static let log = Logger(subsystem: "app.smart-note.together", category: "api")

    init(baseURL: URL = APIConfig.baseURL, session: URLSession = .shared, vault: TokenVault?,
         signedOut: @escaping @Sendable () async -> Void = {}) {
        self.baseURL = baseURL
        self.session = session
        self.vault = vault
        self.signedOut = signedOut
    }

    /// Decodes a JSON answer.
    func send<T: Decodable>(_ request: APIRequest, as type: T.Type = T.self) async throws -> T {
        let (data, _) = try await raw(request)
        do {
            return try APICoding.decoder.decode(T.self, from: data)
        } catch {
            Self.log.error("decode \(String(describing: T.self), privacy: .public) for \(request.method, privacy: .public) \(request.path, privacy: .public): \(String(describing: error), privacy: .public)")
            throw APIError.badResponse("\(T.self): \(error)")
        }
    }

    /// For answers without a body we need (204, or one we ignore).
    func send(_ request: APIRequest) async throws {
        _ = try await raw(request)
    }

    /// The body and response of a 2xx, after the auth dance. Errors are `APIError`.
    func raw(_ request: APIRequest) async throws -> (Data, HTTPURLResponse) {
        let token = request.authenticated ? await vault?.accessToken : nil
        let (data, response) = try await perform(request, token: token)
        guard response.statusCode == 401, request.authenticated, let vault else {
            return try Self.check(data, response)
        }
        let code = Self.errorCode(data)
        guard code == "invalid_access_token" else {
            await signedOut()
            throw APIError.signedOut
        }
        let fresh: String
        do {
            fresh = try await vault.refresh(after: token)
        } catch APIError.signedOut {
            await signedOut()
            throw APIError.signedOut
        }
        let (retryData, retryResponse) = try await perform(request, token: fresh)
        if retryResponse.statusCode == 401 {
            await signedOut()
            throw APIError.signedOut
        }
        return try Self.check(retryData, retryResponse)
    }

    /// A long-lived streaming GET (the space's event stream): bytes as they come.
    func stream(_ request: APIRequest) async throws -> (URLSession.AsyncBytes, HTTPURLResponse) {
        var token = await vault?.accessToken
        for attempt in 0..<2 {
            var urlRequest = try makeURLRequest(request, token: token)
            urlRequest.timeoutInterval = 3600
            let (bytes, response) = try await mapOffline { try await self.session.bytes(for: urlRequest) }
            guard let http = response as? HTTPURLResponse else { throw APIError.badResponse("not HTTP") }
            if http.statusCode == 401, attempt == 0, let vault {
                do { token = try await vault.refresh(after: token) } catch APIError.signedOut {
                    await signedOut()
                    throw APIError.signedOut
                }
                continue
            }
            if !(200..<300).contains(http.statusCode) {
                var body = Data()
                for try await byte in bytes.prefix(4096) { body.append(byte) }
                _ = try Self.check(body, http) // throws the API's error
                throw APIError.badResponse("HTTP \(http.statusCode)")
            }
            return (bytes, http)
        }
        await signedOut()
        throw APIError.signedOut
    }

    // MARK: Private

    private func perform(_ request: APIRequest, token: String?) async throws -> (Data, HTTPURLResponse) {
        let urlRequest = try makeURLRequest(request, token: token)
        let requestID = urlRequest.value(forHTTPHeaderField: "X-Request-Id") ?? "-"
        let started = Date()
        let (data, response) = try await mapOffline { try await self.session.data(for: urlRequest) }
        guard let http = response as? HTTPURLResponse else { throw APIError.badResponse("not HTTP") }
        let ms = Int(Date().timeIntervalSince(started) * 1000)
        Self.log.info("\(request.method, privacy: .public) \(request.path, privacy: .public) → \(http.statusCode) in \(ms) ms [\(requestID, privacy: .public)]")
        return (data, http)
    }

    private func makeURLRequest(_ request: APIRequest, token: String?) throws -> URLRequest {
        var components = URLComponents(url: baseURL.appending(path: request.path), resolvingAgainstBaseURL: false)
        if !request.query.isEmpty { components?.queryItems = request.query }
        guard let url = components?.url else { throw APIError.badResponse("bad URL \(request.path)") }
        var urlRequest = URLRequest(url: url, timeoutInterval: request.timeout)
        urlRequest.httpMethod = request.method
        urlRequest.httpBody = request.body
        urlRequest.setValue(String(UUID().uuidString.prefix(18)).lowercased(), forHTTPHeaderField: "X-Request-Id")
        urlRequest.setValue("application/json", forHTTPHeaderField: "Accept")
        if let contentType = request.contentType { urlRequest.setValue(contentType, forHTTPHeaderField: "Content-Type") }
        if let token { urlRequest.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        for (name, value) in request.headers { urlRequest.setValue(value, forHTTPHeaderField: name) }
        return urlRequest
    }

    private func mapOffline<T>(_ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch let error as URLError where APIError.offlineCodes.contains(error.code) {
            throw APIError.offline
        } catch let error as URLError where error.code == .cancelled {
            throw CancellationError()
        }
    }

    static func check(_ data: Data, _ response: HTTPURLResponse) throws -> (Data, HTTPURLResponse) {
        guard !(200..<300).contains(response.statusCode) else { return (data, response) }
        struct Body: Decodable {
            struct Inner: Decodable { var code: String; var message: String }
            var error: Inner
        }
        let parsed = try? JSONDecoder().decode(Body.self, from: data)
        throw APIError.server(
            status: response.statusCode,
            code: parsed?.error.code ?? "http_\(response.statusCode)",
            message: parsed?.error.message ?? "Something went wrong. Try again in a moment.",
            retryAfter: response.value(forHTTPHeaderField: "Retry-After").flatMap { Int($0) },
            body: data
        )
    }

    private static func errorCode(_ data: Data) -> String? {
        struct Body: Decodable {
            struct Inner: Decodable { var code: String }
            var error: Inner
        }
        return (try? JSONDecoder().decode(Body.self, from: data))?.error.code
    }
}
