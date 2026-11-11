import os
import SwiftUI
import UIKit

/// The API side of the app, built once in `AppRoot` when not running on fakes: the token vault, the client and the
/// services the screens use. Screens get it from the environment (`\.backend`); `nil` means fakes (UI tests,
/// screenshots, previews).
@MainActor
final class Backend {
    let vault: TokenVault
    let client: APIClient
    let push = PushRegistration()

    var auth: APIAuthService { APIAuthService(client: client) }
    var invites: APIInviteService { APIInviteService(client: client) }

    init(tokens: AuthTokens?, session: @escaping @MainActor () -> Session?, baseURL: URL = APIConfig.baseURL) {
        vault = TokenVault(
            tokens: tokens,
            rotate: { refreshToken in try await APIAuthService.refresh(refreshToken, baseURL: baseURL) },
            didChange: { tokens in await MainActor.run { session()?.tokensRotated(tokens) } }
        )
        client = APIClient(baseURL: baseURL, vault: vault) {
            await MainActor.run { session()?.signedOutByServer() }
        }
    }

    /// A receipt recognizer that sends the photos to this API.
    func receiptRecognizer(spaceID: @escaping @MainActor @Sendable (SpaceKind) -> UUID?) -> ReceiptRecognizer {
        APIReceiptRecognizer(client: client, spaceID: { kind in await spaceID(kind) })
    }
}

private struct BackendKey: EnvironmentKey {
    static let defaultValue: Backend? = nil
}

extension EnvironmentValues {
    var backend: Backend? {
        get { self[BackendKey.self] }
        set { self[BackendKey.self] = newValue }
    }
}

/// Registers this phone's APNs token with `POST /v1/me/devices` (every launch, as the API asks) and forgets it on
/// sign-out. Real pushes need the APNs key on the server and the Push capability here; without them iOS reports
/// a failure and nothing is sent.
@MainActor
final class PushRegistration {
    static var current: PushRegistration?
    private var client: APIClient?
    private(set) var token: String?
    private static let log = Logger(subsystem: "app.smart-note.together", category: "push")

    /// Signed in: ask iOS for a token (it arrives in the app delegate).
    func start(client: APIClient) {
        self.client = client
        Self.current = self
        UIApplication.shared.registerForRemoteNotifications()
        if token != nil { Task { await register() } }
    }

    func received(_ deviceToken: Data) {
        token = deviceToken.map { String(format: "%02x", $0) }.joined()
        Task { await register() }
    }

    func register() async {
        guard let client, let token else { return }
        #if DEBUG
        let environment = "sandbox"
        #else
        let environment = "production"
        #endif
        do {
            try await client.send(.send("POST", "v1/me/devices", json: DeviceBody(token: token, environment: environment)))
        } catch {
            Self.log.error("device registration failed: \(String(describing: error), privacy: .public)")
        }
    }

    /// Sign-out: this phone shouldn't get the account's pushes any more.
    func unregister() async {
        guard let client, let token else { return }
        try? await client.send(.delete("v1/me/devices/\(token)"))
        self.client = nil
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate {
    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        MainActor.assumeIsolated { PushRegistration.current?.received(deviceToken) }
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        Logger(subsystem: "app.smart-note.together", category: "push")
            .info("no APNs token: \(error.localizedDescription, privacy: .public)")
    }
}
