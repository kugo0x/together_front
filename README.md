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
UI tests launch the app with `-noNotifications YES` so no permission alert appears.

Launch arguments for checks and screenshots: `-initialTab home|groceries|tasks|notes`, `-activeSpace shared|personal`,
`-noNotifications YES`, `-demoToast partner|undo`, `-catalog YES` (design-system catalog).

## Layout

- `Together/DesignSystem/Tokens.swift` — copied verbatim from `../design/ios/Tokens.swift`. Don't edit; re-copy when tokens change.
- `Together/DesignSystem/Foundation/` — non-token metrics (`DS`), shadows (`TG.Shadow`), layouts (`FlowLayout`, `TGGroup`), `QuantityParser` (port of `parseQty`).
- `Together/DesignSystem/Components/` — one file per design-system component, each with `#Preview` in light and dark.
- `Together/DesignSystem/Catalog/` — `ComponentCatalog` (all galleries; open with `-catalog YES`).
- `Together/Model/` — client model (HANDOFF §4), mock data, task rules (mirror of `back/internal/task/domain`).
- `Together/Store/` — in-memory `AppStore` (methods shaped like the backend API) and reminder notifications.
- `Together/Shell/` — tab shell, global space, toast overlay; `Together/Features/` — Groceries, Tasks.
- `TogetherTests/` — unit tests (Swift Testing) and an opt-in snapshot renderer; `TogetherUITests/` — XCUITest flows.

The design system lives in the app module (not a separate package) because the generated `Tokens.swift` uses internal access.

## Compare with the design screenshots

```bash
TEST_RUNNER_SNAPSHOT_DIR=$PWD/build/snapshots xcodebuild test -project Together.xcodeproj -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ComponentSnapshotTests
```

Writes `build/snapshots/<Component>-light.png` / `-dark.png` at the size and scale of `../design/screenshots/components/`.
