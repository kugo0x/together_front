import Foundation

/// The active space is one global setting, sticky across tabs and launches (HANDOFF §2.1).
/// Read and write it with `@AppStorage(SpaceSetting.key)`; only `RootView` should own it.
enum SpaceSetting {
    static let key = "activeSpace"
    static let defaultValue: SpaceKind = .shared
}

import SwiftUI

/// Switches the global space from inside a screen — e.g. a note moved to Shared takes the app with it, and its
/// Undo goes back to Personal (prototype `confirmMove`). Use `@Environment(\.selectSpace)` and call it.
struct SelectSpaceAction {
    let action: @MainActor @Sendable (SpaceKind) -> Void

    @MainActor
    func callAsFunction(_ space: SpaceKind) { action(space) }
}

private struct SelectSpaceKey: EnvironmentKey {
    static let defaultValue = SelectSpaceAction { _ in }
}

extension EnvironmentValues {
    var selectSpace: SelectSpaceAction {
        get { self[SelectSpaceKey.self] }
        set { self[SelectSpaceKey.self] = newValue }
    }
}
