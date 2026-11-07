import Foundation

/// The active space is one global setting, sticky across tabs and launches (HANDOFF §2.1).
/// Read and write it with `@AppStorage(SpaceSetting.key)`; only `RootView` should own it.
enum SpaceSetting {
    static let key = "activeSpace"
    static let defaultValue: SpaceKind = .shared
}
