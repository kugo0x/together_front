import SwiftUI

/// Task actions with their toasts, the same on Tasks and Home: complete (repeating ones roll) with Undo,
/// delete with Undo, and the "Reminder set for …" / "Sam will be reminded …" confirmations after creating.
@MainActor
struct TaskFlows {
    let store: AppStore
    let toasts: ToastCenter
    let space: SpaceKind
    var reduceMotion = false

    private var animation: Animation { .tg(.easeInOut(duration: 0.2), reduceMotion: reduceMotion) }

    /// Completes an open task, or reopens a done one (no toast for that).
    func toggle(_ id: TaskItem.ID, done: Bool) {
        let store = store, space = space
        if done {
            withAnimation(animation) { _ = store.reopenTask(id, in: space) }
            return
        }
        guard let result = withAnimation(animation, { store.completeTask(id, in: space) }) else { return }
        let undo: @MainActor () -> Void = { _ = store.reopenTask(id, in: space) }
        if result.rolled, let next = result.task.dueDay {
            toasts.showUndo("Done · next one " + store.dates.due(next.at(calendar: store.calendar)), undo: undo)
        } else {
            toasts.showUndo("Task done", undo: undo)
        }
    }

    func delete(_ id: TaskItem.ID) {
        let store = store
        guard let removed = store.deleteTask(id, in: space) else { return }
        toasts.showUndo("Task deleted") { store.undoDeleteTask(removed) }
    }

    func create(_ draft: AppStore.TaskDraft) {
        guard let task = store.createTask(draft, in: space) else { return }
        if let reminder = task.reminder {
            let when = store.dates.reminder(reminder.remindAt)
            toasts.show(reminder.recipient == store.me ? "Reminder set for \(when)" : "\(reminder.recipient.name) will be reminded \(when)")
        } else if let assignee = task.assignee, assignee == store.partner, assignee != store.me {
            toasts.show("Added · \(assignee.name) will see it in Tasks")
        } else {
            toasts.show("Task added")
        }
    }
}
