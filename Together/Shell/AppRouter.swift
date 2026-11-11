import Observation

/// App-level navigation that crosses tabs: Home's quick actions and rows open other tabs (and things in them).
/// Get it with `@Environment(AppRouter.self)`. Requests are one-shot: the receiving screen clears them.
@MainActor
@Observable
final class AppRouter {
    var tab: AppTab

    /// Groceries should focus its QuickAdd field.
    var focusQuickAdd = false
    /// Notes should open this note's editor.
    var openNote: Note.ID?

    init(tab: AppTab = .home) {
        self.tab = tab
    }

    func addGrocery() {
        focusQuickAdd = true
        tab = .groceries
    }

    func open(_ note: Note.ID) {
        openNote = note
        tab = .notes
    }
}
