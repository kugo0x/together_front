import Foundation

/// An invite into the Shared space (back/api/openapi.yaml `Invite`): code `TGT-XXXX` + universal link.
struct Invite: Equatable, Sendable {
    var code: String
    var link: URL
    var expiresAt: Date
}

enum InviteError: Error, Equatable {
    /// Not a `TGT-XXXX` code.
    case invalidCode
    /// 404 `invite_not_found` — no such code, or it expired.
    case notFound
    /// Anything else the API said (`already_in_shared_space`, `own_invite`…), in its words.
    case server(message: String)

    var message: String {
        switch self {
        case .invalidCode: "Codes look like TGT-7KQ2."
        case .notFound: "That code didn’t work. Ask for a new invite."
        case .server(let message): message
        }
    }
}

enum InviteCode {
    /// Case-insensitive; `TGT-7KQ2`, `tgt7kq2` and `7KQ2` are the same code. `nil` if it can't be one.
    static func normalize(_ input: String) -> String? {
        var raw = input.uppercased().filter { $0.isLetter || $0.isNumber }
        if raw.hasPrefix("TGT") { raw.removeFirst(3) }
        guard raw.count == 4, raw.allSatisfy({ $0.isASCII && ($0.isNumber || $0.isUppercase) }) else { return nil }
        return "TGT-" + raw
    }
}

/// `POST /v1/spaces/{id}/invites`, `POST /v1/invites/{code}/accept`, and the `space.member_joined` event.
protocol InviteService: Sendable {
    func createInvite() async throws -> Invite
    /// Join someone else's Shared space with their code; returns who invited you.
    func accept(code: String) async throws -> Person
    /// Waits for the invite to be accepted (the real app hears `space.member_joined` on the event stream).
    func waitForJoin(_ invite: Invite) async throws -> Person
}

/// Stand-in: Sam accepts shortly after the link is shared; any well-formed code but TGT-0000 is accepted.
struct FakeInviteService: InviteService {
    var joinDelay: Duration = .milliseconds(1500)
    var now: @Sendable () -> Date = { .now }

    func createInvite() async throws -> Invite {
        let alphabet = Array("23456789ABCDEFGHJKLMNPQRSTUVWXYZ")
        let code = "TGT-" + String((0..<4).map { _ in alphabet.randomElement()! })
        return Invite(code: code, link: URL(string: "https://together.app/invite/\(code)")!,
                      expiresAt: now().addingTimeInterval(7 * 24 * 3600))
    }

    func accept(code: String) async throws -> Person {
        guard let code = InviteCode.normalize(code) else { throw InviteError.invalidCode }
        guard code != "TGT-0000" else { throw InviteError.notFound }
        return .sam
    }

    func waitForJoin(_ invite: Invite) async throws -> Person {
        try await Task.sleep(for: joinDelay)
        return .sam
    }
}
