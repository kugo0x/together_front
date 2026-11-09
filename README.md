# Together — iOS client

SwiftUI, iOS 17+, Swift 6. The Xcode project is generated from `project.yml` with [XcodeGen](https://github.com/yonaskolb/XcodeGen) and is not checked in.

## Build

```bash
brew install xcodegen      # once
xcodegen generate          # after cloning or editing project.yml / adding files
open Together.xcodeproj
```

Command line (simulator):

```bash
xcrun simctl boot "iPhone 17 Pro"   # first run only; launching fails on a shut-down simulator
xcodebuild test -project Together.xcodeproj -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -collect-test-diagnostics never
```

Runs the unit tests (`TogetherTests`) and the UI tests (`TogetherUITests`, ~2 min).
`-collect-test-diagnostics never` stops xcodebuild from spending up to 10 minutes on a sysdiagnose after a failure.
UI tests launch the app with `-noNotifications YES` so no permission alert appears, and with `-signedIn YES` or
`-signedOut YES` (both keep the session in memory and never touch the real Keychain).

Launch arguments for checks and screenshots: `-signedIn YES` (start signed in as Alex), `-signedOut YES` (start at the
welcome screen), `-initialTab home|groceries|tasks|notes`, `-initialSpace shared|personal` (sets the starting space; switching still works),
`-noNotifications YES`, `-alone YES` (no partner yet: invite banner), `-demoToast partner|undo`, `-catalog YES` (design-system catalog).

## Layout

- `Together/DesignSystem/Tokens.swift` — copied verbatim from `../design/ios/Tokens.swift`. Don't edit; re-copy when tokens change.
- `Together/DesignSystem/Foundation/` — non-token metrics (`DS`), shadows (`TG.Shadow`), layouts (`FlowLayout`, `TGGroup`), `QuantityParser` (port of `parseQty`).
- `Together/DesignSystem/Components/` — one file per design-system component, each with `#Preview` in light and dark.
- `Together/DesignSystem/Catalog/` — `ComponentCatalog` (all galleries; open with `-catalog YES`).
- `Together/Model/` — client model (HANDOFF §4), mock data, task rules (mirror of `back/internal/task/domain`).
- `Together/Store/` — in-memory `AppStore` (methods shaped like the backend API) and reminder notifications.
- `Together/Auth/` — `Session` (signed out → onboarding → signed in), `AuthService` (fake for now, shaped like
  `/v1/auth/*`), Keychain wrapper, invites, Apple/Google sign-in helpers. `Together/App/AppRoot.swift` switches on the session.
- `Together/Shell/` — tab shell, global space, router, toast overlay; `Together/Features/` — Onboarding, Home,
  Groceries, Tasks, Notes, Settings.
- `TogetherTests/` — unit tests (Swift Testing) and an opt-in snapshot renderer; `TogetherUITests/` — XCUITest flows.

The design system lives in the app module (not a separate package) because the generated `Tokens.swift` uses internal access.

## Compare with the design screenshots

```bash
TEST_RUNNER_SNAPSHOT_DIR=$PWD/build/snapshots xcodebuild test -project Together.xcodeproj -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ComponentSnapshotTests
```

Writes `build/snapshots/<Component>-light.png` / `-dark.png` at the size and scale of `../design/screenshots/components/`.

## Sign in with Apple and Google

Both buttons are the official ones (`SignInWithAppleButton`, Google's `GoogleSignInButton` from the
`GoogleSignIn-iOS` package) — never redraw their logos. Until the following is supplied, tapping them shows
"… sign-in isn’t set up in this build yet" instead of failing silently. Email + password works without any setup
(the fake service is seeded with `alex@example.com` / `together123`).

**Apple** (needs a paid Apple Developer team):

1. Set `DEVELOPMENT_TEAM` in `project.yml` and a real `PRODUCT_BUNDLE_IDENTIFIER`.
2. Add the capability: an entitlements file with `com.apple.developer.applesignin = [Default]`, referenced from
   `project.yml` (`entitlements: path: Together/Together.entitlements`), and enable "Sign in with Apple" for the App ID.
3. The backend needs the bundle ID in `APPLE_CLIENT_IDS` (Railway variable) to verify identity tokens.

**Google**:

1. Create an iOS OAuth client in Google Cloud Console for the bundle ID.
2. Add to Info.plist (via `project.yml` → `info:` properties, since the plist is generated):
   - `GIDClientID` = the iOS client ID (`1234-abc.apps.googleusercontent.com`)
   - `CFBundleURLTypes` → one URL scheme = the *reversed* client ID (`com.googleusercontent.apps.1234-abc`)
3. The backend needs the same client ID in `GOOGLE_CLIENT_IDS` to verify ID tokens.

`GoogleSDKSignIn` checks for `GIDClientID` first, because the SDK throws an exception without it.
