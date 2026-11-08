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

    // MARK: Actions (shared with Home)

    private var flows: TaskFlows { TaskFlows(store: store, toasts: toasts, space: space, reduceMotion: reduceMotion) }
    private func toggle(_ task: TaskItem) { flows.toggle(task.id, done: task.done) }
    private func delete(_ task: TaskItem) { flows.delete(task.id) }
    private func create(_ draft: AppStore.TaskDraft) { flows.create(draft) }
}
