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

## The API

The app talks to the Go API in `../back` (`back/api/openapi.yaml`). **Debug** builds use `http://localhost:8080`,
the local stack: in `../back`, `make dev-up && make dev-seed` starts Postgres and the API in Docker and creates Alex
and Sam in one Shared space (their test logins are in `../back/dev/seed-users.env`). **Release** builds use the
Railway service. The URL comes from one place: the `API_BASE_URL` build setting per configuration in `project.yml`
(→ `APIBaseURL` in Info.plist → `APIConfig.baseURL`). `-apiBaseURL <url>` overrides it.

- `Together/API/APIClient.swift` — one URLSession client: a request ID on every call, typed `APIError`s from the
  API's error format, 401 `invalid_access_token` → one refresh (single-flight, refresh tokens are single use) →
  retry, any other 401 → signed out. Logs method, path, status and request ID only.
- `APIModels.swift` — wire models, checked against the spec by `APISpecTests` (copy of the spec in
  `TogetherTests/Resources/openapi.json`; refresh it with `scripts/update-openapi.sh` after the backend changes it).
- `RemoteSync.swift` — fills `AppStore` from the server (requests in parallel; the last load is kept on disk by
  `SyncCache.swift` and shown at once on the next launch, removed at sign-out; partner events heard during a load
  are applied again on top of it) and sends every change in order. Changes show at once
  (optimistic); a refused one is undone, the space re-fetched and a toast says why. Offline, changes wait (the banner
  says so; grocery items typed offline are kept on disk until sent). While in the foreground each space's event
  stream applies the partner's changes ("Sam bought Tomatoes") and re-fetches after a reconnect.
- `APIServices.swift` — sign-in/up (email, Apple, Google), invites; `Backend.swift` — wiring, push registration
  (`POST /v1/me/devices`; real pushes need the APNs key on the server and the Push capability here).

UI tests and screenshots run on fakes, without a server: `-signedIn YES`, `-signedOut YES`, or `-fakeBackend YES`.

### Integration tests (opt-in)

Against the local stack (fresh seed: `make dev-reset`), with the seeded logins from the environment — never committed:

```bash
set -a; source ../back/dev/seed-users.env; set +a
TEST_RUNNER_INTEGRATION=1 TEST_RUNNER_API_BASE_URL=http://localhost:8080 \
TEST_RUNNER_SEED_ALEX_EMAIL=$SEED_ALEX_EMAIL TEST_RUNNER_SEED_ALEX_PASSWORD=$SEED_ALEX_PASSWORD \
TEST_RUNNER_SEED_SAM_EMAIL=$SEED_SAM_EMAIL TEST_RUNNER_SEED_SAM_PASSWORD=$SEED_SAM_PASSWORD \
xcodebuild test -project Together.xcodeproj -scheme Together -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:TogetherTests/APILiveTests -only-testing:TogetherUITests/IntegrationUITests
```

`APILiveTests` drive the sync layer as Alex and Sam on two "phones" (realtime, offline queue, conflicts, receipts,
invites, settings); `IntegrationUITests` use the real app as Alex and play Sam over HTTP. The API allows 10 sign-ins
per email per 15 minutes, so the suites sign in once per run. Each run changes the seeded data (a receipt trip, a
dismissed suggestion) — reset with `make dev-reset` before the next one.

## Launch arguments

For checks and screenshots: `-signedIn YES` (start signed in as Alex), `-signedOut YES` (start at the
welcome screen), `-initialTab home|groceries|tasks|notes`, `-initialSpace shared|personal` (sets the starting space; switching still works),
`-noNotifications YES`, `-alone YES` (no partner yet: invite banner), `-demoToast partner|undo`, `-catalog YES` (design-system catalog),
`-apiBaseURL <url>`, `-resetSession YES` (start signed out on the API — integration tests), `-fakeBackend YES`.

Receipts (no camera in the simulator): `-receiptPhotos N` opens Scan receipt with N blank photos (N > 1 asks
"parts of one receipt" vs "separate receipts"), `-receiptSeparate YES|NO` answers that question,
`-receiptFixture <name>` picks what the stand-in recognizer answers (corner, biedronka, mismatch, offline, unreadable,
notReceipt, tooLong, busy, limit, disabled) (`corner,biedronka`
answers each receipt of a queue with the next one), `-receiptDelay <ms>` sets how long "reading" takes (default 2500).

## Receipts

Recognition happens on the backend (`POST /v1/spaces/{id}/receipts/scan`, Claude API — the key never ships in the
app). The app only prepares the photos (`ReceiptImage`: JPEG, long side ≤ 2576 px and ≤ 3.75 MP, ≤ 3.8 MB each, no metadata), sends 1–5 photos
of one receipt per call (`ReceiptRecognizer`) and shows the server's matching for review; nothing changes until
Confirm. Several different receipts are a queue (`ReceiptScanFlow`): read in parallel, reviewed one by one, a trip
each. Signed in against the API, `APIReceiptRecognizer` sends the photos (back `api/openapi.yaml` 0.8.0,
`docs/receipt-scan.md`; the local stack answers with a demo receipt unless it has an Anthropic key). On fakes, the
fixture-backed `FakeReceiptRecognizer` answers.

## Layout

- `Together/DesignSystem/Tokens.swift` — copied verbatim from `../design/ios/Tokens.swift`. Don't edit; re-copy when tokens change.
- `Together/DesignSystem/Foundation/` — non-token metrics (`DS`), shadows (`TG.Shadow`), layouts (`FlowLayout`, `TGGroup`), `QuantityParser` (port of `parseQty`).
- `Together/DesignSystem/Components/` — one file per design-system component, each with `#Preview` in light and dark.
- `Together/DesignSystem/Catalog/` — `ComponentCatalog` (all galleries; open with `-catalog YES`).
- `Together/Model/` — client model (HANDOFF §4), mock data, task rules (mirror of `back/internal/task/domain`).
- `Together/Store/` — `AppStore` (the app's state; methods shaped like the backend API, every change reported to
  `StoreSync`) and reminder notifications.
- `Together/API/` — client, wire models, sync, event streams, API services (see "The API").
- `Together/Auth/` — `Session` (signed out → onboarding → signed in), `AuthService` (API or fake), Keychain wrapper,
  invites, Apple/Google sign-in helpers. `Together/App/AppRoot.swift` switches on the session.
- `Together/Receipts/` — receipt scan model: recognizer protocol (API + stand-in), fixtures, image prep, scan
  flow, review.
- `Together/Shell/` — tab shell, global space, router, toast overlay; `Together/Features/` — Onboarding, Home,
  Groceries, Receipts (scan sheet, History), Tasks, Notes, Settings.
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

**Apple**: set up — team `9GR42Q72Q6`, bundle ID `app.smart-note.together` (App ID with Push Notifications and
Sign in with Apple), entitlements in `project.yml` (`entitlements:` → `Together/Together.entitlements`).
The backend needs the bundle ID in `APPLE_CLIENT_IDS` (Railway variable) to verify identity tokens.

**Google**:

1. Create an iOS OAuth client in Google Cloud Console for the bundle ID.
2. Add to Info.plist (via `project.yml` → `info:` properties, since the plist is generated):
   - `GIDClientID` = the iOS client ID (`1234-abc.apps.googleusercontent.com`)
   - `CFBundleURLTypes` → one URL scheme = the *reversed* client ID (`com.googleusercontent.apps.1234-abc`)
3. The backend needs the same client ID in `GOOGLE_CLIENT_IDS` to verify ID tokens.

`GoogleSDKSignIn` checks for `GIDClientID` first, because the SDK throws an exception without it.
