import OSLog
import SwiftUI

/// One toast at a time, auto-hidden after 3.8 s; a new toast replaces the current one.
/// Get it with `@Environment(ToastCenter.self)` and call `show(...)`.
@MainActor
@Observable
final class ToastCenter {
    struct Item: Identifiable {
        let id = UUID()
        var message: String
        var person: Person?
        var action: String?
        var onAction: (@MainActor () -> Void)?
    }

    /// Waits for a duration; injectable so tests can drive time by hand.
    typealias Sleep = @Sendable (Duration) async throws -> Void

    static let duration: Duration = .milliseconds(3800)
    private static let log = Logger(subsystem: "app.smart-note.together", category: "toast")

    private(set) var current: Item?
    @ObservationIgnored private var hideTask: Task<Void, Never>?
    @ObservationIgnored private let duration: Duration
    @ObservationIgnored private let sleep: Sleep

    init(duration: Duration = ToastCenter.duration, sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.duration = duration
        self.sleep = sleep
    }

    func show(_ message: String, person: Person? = nil, action: String? = nil, onAction: (@MainActor () -> Void)? = nil) {
        let item = Item(message: message, person: person, action: action, onAction: onAction)
        current = item
        Self.log.debug("show \(message, privacy: .public)")
        AccessibilityNotification.Announcement(action.map { "\(message). \($0) available" } ?? message).post()
        hideTask?.cancel()
        hideTask = Task { [weak self, duration, sleep] in
            try? await sleep(duration)
            guard !Task.isCancelled else { return }
            self?.dismiss(item.id)
        }
    }

    /// Convenience for the common "X done · Undo" toast.
    func showUndo(_ message: String, undo: @escaping @MainActor () -> Void) {
        show(message, action: "Undo", onAction: undo)
    }

    /// Runs the toast's action and hides it.
    func performAction() {
        let action = current?.onAction
        dismiss()
        action?()
    }

    func dismiss(_ id: Item.ID? = nil) {
        guard let current, id == nil || current.id == id else { return }
        Self.log.debug("hide \(current.message, privacy: .public)")
        self.current = nil
        hideTask?.cancel()
        hideTask = nil
    }
}

/// Shows the current toast bottom-centre, above the tab bar (the modified view's bottom safe-area edge).
struct ToastHost: ViewModifier {
    /// Off where a screen hosts the toast itself (Groceries, to sit above its QuickAdd bar).
    var enabled = true
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay(alignment: .bottom) {
            ZStack {
                if enabled, let item = toasts.current {
                    Toast(message: item.message, person: item.person, action: item.action) {
                        toasts.performAction()
                    }
                    .id(item.id)
                    .padding(.horizontal, TG.Space.s4)
                    .padding(.bottom, TG.Space.s3)
                    .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.tg(.spring(duration: 0.24, bounce: 0), reduceMotion: reduceMotion), value: toasts.current?.id)
        }
    }
}

extension View {
    func toastHost(enabled: Bool = true) -> some View { modifier(ToastHost(enabled: enabled)) }
}
