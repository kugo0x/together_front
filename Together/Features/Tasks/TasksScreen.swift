import SwiftUI

/// Tasks (HANDOFF §6.4): New task, To do (by due date, undated last), Done. Completing shows Undo;
/// a repeating task rolls to its next date instead of moving to Done. Swipe to delete with Undo; tap to edit.
struct TasksScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.space) private var space
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var sheet: TaskSheet.Mode?

    var body: some View {
        TimelineView(.everyMinute) { _ in
            list(dates: store.dates)
        }
        .sheet(item: $sheet) { mode in
            switch mode {
            case .new:
                TaskSheet(mode: mode) { create($0) }
            case .edit(let task):
                TaskSheet(mode: mode) { draft in
                    store.updateTask(task.id, in: space, with: draft)
                } onDelete: {
                    delete(task)
                }
            }
        }
    }

    private func list(dates: RelativeDate) -> some View {
        let active = store.activeTasks(in: space)
        let done = store.doneTasks(in: space)

        return ShellList(subtitle: subtitle(active: active.count)) {
            Section {
                TGButton("New task", icon: .plus, variant: .tinted, block: true) { sheet = .new }
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
            }

            ShellSection(title: "To do", count: active.count) {
                if active.isEmpty {
                    EmptyState(title: "All done", message: "Nothing left to do here. New tasks only need a title.", icon: .tasks)
                } else {
                    ForEach(active) { task in row(task, dates: dates) }
                }
            }

            if !done.isEmpty {
                ShellSection(title: "Done", count: done.count) {
                    ForEach(done) { task in row(task, dates: dates) }
                }
            }
        }
    }

    private func row(_ task: TaskItem, dates: RelativeDate) -> some View {
        TaskRow(task: task, dates: dates, me: store.me) { toggle(task) }
            .contentShape(Rectangle())
            .onTapGesture { sheet = .edit(task) }
            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                Button(role: .destructive) { delete(task) } label: {
                    Label("Delete", systemImage: IconName.trash.systemName)
                }
                .tint(TG.Colors.danger)
            }
            .accessibilityAction(named: "Edit") { sheet = .edit(task) }
            .accessibilityAction(named: "Delete") { delete(task) }
    }

    private func subtitle(active: Int) -> String {
        let who = space == .shared ? store.partner.map { "Shared with \($0.name)" } ?? "Shared space" : "Private"
        return "\(active) to do · \(who)"
    }

    // MARK: Actions

    private func toggle(_ task: TaskItem) {
        let space = space
        let animation = Animation.tg(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)
        if task.done {
            withAnimation(animation) { _ = store.reopenTask(task.id, in: space) }
            return
        }
        guard let result = withAnimation(animation, { store.completeTask(task.id, in: space) }) else { return }
        let undo: @MainActor () -> Void = { _ = store.reopenTask(task.id, in: space) }
        if result.rolled, let next = result.task.dueDay {
            toasts.showUndo("Done · next one " + store.dates.due(next.at(calendar: store.calendar)), undo: undo)
        } else {
            toasts.showUndo("Task done", undo: undo)
        }
    }

    private func delete(_ task: TaskItem) {
        guard let removed = store.deleteTask(task.id, in: space) else { return }
        toasts.showUndo("Task deleted") { store.undoDeleteTask(removed) }
    }

    private func create(_ draft: AppStore.TaskDraft) {
        guard let task = store.createTask(draft, in: space) else { return }
        let partner = store.partner
        if let reminder = task.reminder {
            let when = store.dates.reminder(reminder.remindAt)
            toasts.show(reminder.recipient == store.me ? "Reminder set for \(when)" : "\(reminder.recipient.name) will be reminded \(when)")
        } else if let assignee = task.assignee, assignee == partner, assignee != store.me {
            toasts.show("Added · \(assignee.name) will see it in Tasks")
        } else {
            toasts.show("Task added")
        }
    }
}
