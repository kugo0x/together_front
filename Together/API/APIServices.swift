import Foundation

/// `AuthService` over the real API (`/v1/auth/*`, `/v1/me`). Errors become the `AuthError`s the screens show.
struct APIAuthService: AuthService {
    let client: APIClient

    func register(email: String, password: String, displayName: String?) async throws -> AuthResult {
        try await auth(.send("POST", "v1/auth/register",
                             json: RegisterBody(email: email.trimmingCharacters(in: .whitespaces), password: password,
                                                displayName: displayName), authenticated: false))
    }

    func login(email: String, password: String) async throws -> AuthResult {
        try await auth(.send("POST", "v1/auth/login",
                             json: LoginBody(email: email.trimmingCharacters(in: .whitespaces), password: password),
                             authenticated: false))
    }

    func signInWithApple(identityToken: String, nonce: String, displayName: String?) async throws -> AuthResult {
        try await auth(.send("POST", "v1/auth/apple",
                             json: IDTokenBody(idToken: identityToken, nonce: nonce, displayName: displayName),
                             authenticated: false), provider: .apple)
    }

    func signInWithGoogle(idToken: String, nonce: String) async throws -> AuthResult {
        try await auth(.send("POST", "v1/auth/google", json: IDTokenBody(idToken: idToken, nonce: nonce),
                             authenticated: false), provider: .google)
    }

    func forgotPassword(email: String) async throws {
        try await mapped {
            try await client.send(.send("POST", "v1/auth/password/forgot", json: EmailBody(email: email), authenticated: false))
        }
    }

    func updateDisplayName(_ name: String, tokens: AuthTokens) async throws -> AuthUser {
        try await mapped {
            APIMapping.user(try await client.send(.send("PATCH", "v1/me", json: MePatchBody(displayName: name)), as: MeDTO.self))
        }
    }

    func logout(tokens: AuthTokens) async throws {
        try await mapped { try await client.send(.send("POST", "v1/auth/logout")) }
    }

    func deleteAccount(tokens: AuthTokens) async throws {
        try await mapped { try await client.send(.delete("v1/me")) }
    }

    /// The signed-in user (after a restore, to pick up a rename made on the other phone).
    func me() async throws -> AuthUser {
        try await mapped { APIMapping.user(try await client.send(.get("v1/me"), as: MeDTO.self)) }
    }

    /// POST /v1/auth/refresh — single use; `TokenVault` makes sure nobody replays one.
    static func refresh(_ refreshToken: String, baseURL: URL) async throws -> AuthTokens {
        let client = APIClient(baseURL: baseURL, vault: nil)
        let dto = try await client.send(.send("POST", "v1/auth/refresh", json: RefreshBody(refreshToken: refreshToken),
                                              authenticated: false), as: TokensDTO.self)
        return APIMapping.tokens(dto)
    }

    // MARK: Private

    private func auth(_ request: APIRequest, provider: AuthProvider? = nil) async throws -> AuthResult {
        try await mapped(provider: provider) {
            let dto = try await client.send(request, as: AuthResultDTO.self)
            return AuthResult(user: APIMapping.user(dto.user), tokens: APIMapping.tokens(dto.tokens), isNewUser: dto.isNewUser)
        }
    }

    private func mapped<T>(provider: AuthProvider? = nil, _ call: () async throws -> T) async throws -> T {
        do {
            return try await call()
        } catch let error as APIError {
            throw Self.authError(error, provider: provider)
        }
    }

    static func authError(_ error: APIError, provider: AuthProvider? = nil) -> AuthError {
        switch error.code {
        case "invalid_credentials"?: return .invalidCredentials
        case "email_taken"?: return .emailTaken
        case "validation_failed"?:
            let field = error.message.lowercased().contains("password") ? "password" : "email"
            return .validationFailed(field: field)
        case "provider_not_configured"?: return .notConfigured(provider: provider ?? .apple)
        default: break
        }
        if case .offline = error { return .network }
        return .server(message: error.message)
    }
}

/// `InviteService` over the API: the Shared space is created when the first invite is, the inviter waits for
/// the partner (polling the members list — the event stream isn't running during onboarding), and accepting a code
/// joins the inviter's space.
struct APIInviteService: InviteService {
    let client: APIClient

    func createInvite() async throws -> Invite {
        let spaceID = try await sharedSpaceID(create: true)!
        let dto = try await client.send(.send("POST", "v1/spaces/\(spaceID)/invites"), as: InviteDTO.self)
        return Invite(code: dto.code, link: URL(string: dto.link) ?? URL(string: "https://together.app/invite/\(dto.code)")!,
                      expiresAt: dto.expiresAt)
    }

    func accept(code: String) async throws -> Person {
        guard let code = InviteCode.normalize(code) else { throw InviteError.invalidCode }
        do {
            let result = try await client.send(.send("POST", "v1/invites/\(code)/accept"), as: AcceptInviteDTO.self)
            var joined = result.space?.id
            if joined == nil { joined = try await sharedSpaceID(create: false) }
            guard let spaceID = joined else { throw InviteError.notFound }
            let me = try await client.send(.get("v1/me"), as: MeDTO.self)
            let members = try await client.send(.get("v1/spaces/\(spaceID)/members"), as: MembersDTO.self).members
            guard let inviter = ServerDirectory.people(from: members).first(where: { $0.id != me.id }) else {
                throw InviteError.notFound
            }
            return inviter
        } catch let error as APIError {
            switch error.code {
            case "invite_not_found"?, "invite_expired"?, "invite_not_pending"?: throw InviteError.notFound
            default: throw InviteError.server(message: error.message)
            }
        }
    }

    func waitForJoin(_ invite: Invite) async throws -> Person {
        guard let spaceID = try await sharedSpaceID(create: false) else { throw InviteError.notFound }
        let me = try await client.send(.get("v1/me"), as: MeDTO.self)
        while true {
            try Task.checkCancellation()
            if let members = try? await client.send(.get("v1/spaces/\(spaceID)/members"), as: MembersDTO.self).members,
               let partner = ServerDirectory.people(from: members).first(where: { $0.id != me.id }) {
                return partner
            }
            try await Task.sleep(for: .seconds(3))
        }
    }

    private func sharedSpaceID(create: Bool) async throws -> UUID? {
        let spaces = try await client.send(.get("v1/spaces"), as: SpacesDTO.self).spaces
        if let shared = spaces.first(where: { $0.kind == "shared" }) { return shared.id }
        guard create else { return nil }
        return try await client.send(.send("POST", "v1/spaces", json: CreateSpaceBody()), as: SpaceDTO.self).id
    }
}
