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
xcodebuild test -project Together.xcodeproj -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro'
```

## Layout

- `Together/DesignSystem/Tokens.swift` — copied verbatim from `../design/ios/Tokens.swift`. Don't edit; re-copy when tokens change.
- `Together/DesignSystem/Foundation/` — non-token metrics (`DS`), shadows (`TG.Shadow`), layouts (`FlowLayout`, `TGGroup`), `QuantityParser` (port of `parseQty`).
- `Together/DesignSystem/Components/` — one file per design-system component, each with `#Preview` in light and dark.
- `Together/DesignSystem/Catalog/` — `ComponentCatalog` (all galleries; the app's root screen for now).
- `Together/Model/` — shared model types from HANDOFF §4 (`Person`, `Suggestion`).
- `TogetherTests/` — `parseQty` tests (Swift Testing) and an opt-in snapshot renderer.

The design system lives in the app module (not a separate package) because the generated `Tokens.swift` uses internal access.

## Compare with the design screenshots

```bash
TEST_RUNNER_SNAPSHOT_DIR=$PWD/build/snapshots xcodebuild test -project Together.xcodeproj -scheme Together \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:TogetherTests/ComponentSnapshotTests
```

Writes `build/snapshots/<Component>-light.png` / `-dark.png` at the size and scale of `../design/screenshots/components/`.
