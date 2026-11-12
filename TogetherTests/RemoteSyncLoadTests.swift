import Foundation
import UIKit
import Testing
@testable import Together

/// `RemoteSync.loadAll` against a stubbed server: partner events heard mid-load survive the snapshot, and the
/// last load is shown from disk on the next launch.
@Suite(.serialized)
@MainActor
struct RemoteSyncLoadTests {
    /// Answers by path; `onNotes` runs when the notes are asked for, before the (slow) answer.
    final class Stub: URLProtocol, @unchecked Sendable {
        nonisolated(unsafe) static var notesJSON = "[]"
        nonisolated(unsafe) static var onNotes: (@Sendable () -> Void)?
        nonisolated(unsafe) static var offline = false
        /// `/v1/me` answers with this ID and, when set, an avatar URL.
        nonisolated(unsafe) static var meID = UUID()
        nonisolated(unsafe) static var avatarVersion: Int?

        override class func canInit(with request: URLRequest) -> Bool { true }
        override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
        override func stopLoading() {}
        override func startLoading() {
            if Self.offline {
                client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
                return
            }
            let path = request.url!.path
            if path.hasSuffix("/notes") {
                Self.onNotes?()
                Thread.sleep(forTimeInterval: 0.4) // the event arrives while the load is still running
            }
            let body = path.hasSuffix("/avatar") ? RemoteSyncLoadTests.png : Data(RemoteSyncLoadTests.answer(path).utf8)
            let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: nil,
                                           headerFields: ["Content-Type": "application/json"])!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        }
    }

    nonisolated static let space = UUID()
    nonisolated static let list = UUID()
    nonisolated static let sam = UUID()
    nonisolated static let at = "2026-11-09T14:37:00Z"

    nonisolated static func answer(_ path: String) -> String {
        if path.hasSuffix("/v1/me") {
            let avatar = Stub.avatarVersion.map { #"{"url":"/v1/users/\#(Stub.meID)/avatar?v=\#($0)","updated_at":"\#(at)"}"# } ?? "null"
            return #"{"id":"\#(Stub.meID)","email":"a@b.co","email_verified":true,"display_name":"Alex","created_at":"\#(at)","providers":["email"],"time_zone":"Europe/Warsaw","quiet_hours":{"start":"22:00","end":"08:00"},"avatar":\#(avatar)}"#
        }
        if path.hasSuffix("/v1/me/settings") {
            return #"{"time_zone":"Europe/Warsaw","quiet_hours":{"start":"22:00","end":"08:00"},"suggestions_enabled":true,"notifications":{}}"#
        }
        if path.hasSuffix("/v1/spaces") {
            return #"{"spaces":[{"id":"\#(space)","kind":"personal","name":"Personal","created_at":"\#(at)"}]}"#
        }
        if path.hasSuffix("/lists/default") {
            return #"{"list":{"id":"\#(list)","space_id":"\#(space)","name":"Groceries","is_default":true,"created_at":"\#(at)","updated_at":"\#(at)"},"items":[]}"#
        }
        if path.hasSuffix("/suggestions") { return #"{"suggestions":[]}"# }
        if path.hasSuffix("/tasks") { return #"{"tasks":[]}"# }
        if path.hasSuffix("/notes") { return #"{"notes":\#(Stub.notesJSON)}"# }
        if path.hasSuffix("/trips") { return #"{"trips":[]}"# }
        return "{}"
    }

    nonisolated static func note(_ id: UUID, title: String, by actor: UUID) -> String {
        #"{"id":"\#(id)","space_id":"\#(space)","title":"\#(title)","body":"","preview":"","version":1,"items":[],"item_count":0,"done_count":0,"created_by":"\#(actor)","created_at":"\#(at)","updated_by":"\#(actor)","updated_at":"\#(at)"}"#
    }

    static func client() -> APIClient {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [Stub.self]
        return APIClient(baseURL: URL(string: "https://api.test")!, session: URLSession(configuration: config), vault: nil)
    }

    nonisolated static let png: Data = UIGraphicsImageRenderer(size: CGSize(width: 4, height: 4)).pngData { context in
        UIColor.red.setFill()
        context.fill(CGRect(x: 0, y: 0, width: 4, height: 4))
    }

    init() {
        Stub.avatarVersion = nil
        Stub.notesJSON = "[]"
        Stub.onNotes = nil
        Stub.offline = false
    }

    @Test func partnerNoteHeardMidLoadSurvivesTheSnapshot() async throws {
        let store = AppStore(data: .empty)
        let sync = RemoteSync(client: Self.client(), store: store, toasts: ToastCenter(), me: .alex, cachesLoads: false)
        defer { sync.stop() }
        let noteID = UUID()
        let event = try APICoding.decoder.decode(SpaceEventDTO.self, from: Data(
            #"{"type":"note.created","space_id":"\#(Self.space)","actor_id":"\#(Self.sam)","at":"\#(Self.at)","note":\#(Self.note(noteID, title: "Packing list", by: Self.sam))}"#.utf8))
        // The notes were read before Sam's note existed; his event comes in while the rest still loads.
        Stub.onNotes = { Task { @MainActor in sync.apply(event, in: .personal) } }

        await sync.loadAll()

        #expect(store.notes.map(\.title) == ["Packing list"])
    }

    @Test func nextLaunchShowsTheLastLoadFromDisk() async throws {
        let me = Person(id: UUID(), name: "Alex", tint: .alex)
        defer { SyncCache.remove(userID: me.id) }
        Stub.notesJSON = "[\(Self.note(UUID(), title: "Wi-Fi password", by: me.id))]"
        let first = RemoteSync(client: Self.client(), store: AppStore(data: .empty), toasts: ToastCenter(), me: me)
        await first.loadAll()
        first.stop()

        // Relaunch without a connection: the cached load is on screen, no spinner.
        Stub.offline = true
        let store = AppStore(data: .empty)
        store.hasLoaded = false
        let second = RemoteSync(client: Self.client(), store: store, toasts: ToastCenter(), me: me)
        defer { second.stop() }
        await second.loadAll()

        #expect(store.hasLoaded)
        #expect(store.notes.map(\.title) == ["Wi-Fi password"])
        #expect(store.connection == .offline(pending: 0))
    }

    @Test func profilePhotoFromTheServerIsShown() async throws {
        let me = Person(id: UUID(), name: "Alex", tint: .alex)
        Stub.meID = me.id
        Stub.avatarVersion = 1
        let store = AppStore(data: .empty)
        let sync = RemoteSync(client: Self.client(), store: store, toasts: ToastCenter(), me: me, cachesLoads: false)
        defer { sync.stop() }

        await sync.loadAll()
        for _ in 0..<50 where store.avatarPhotos[me.id] == nil { try await Task.sleep(for: .milliseconds(20)) }

        #expect(store.avatarPhotos[me.id] != nil)
        #expect(RemoteSync.avatarRequest("/v1/users/\(me.id)/avatar?v=7")?.path == "v1/users/\(me.id)/avatar")
    }
}
