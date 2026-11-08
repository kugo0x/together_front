import SwiftUI

/// The scrolling body every tab uses: an inset-grouped list on `bg` whose first line is the quiet
/// nav subtitle ("7 to buy · Shared with Sam") under the large title (HANDOFF §3, NavBar).
struct ShellList<Content: View>: View {
    let subtitle: String
    @ViewBuilder var content: Content

    var body: some View {
        List {
            Text(subtitle)
                .font(TG.Font.subhead)
                .foregroundStyle(TG.Colors.ink2)
                .listRowInsets(EdgeInsets(top: 0, leading: TG.Space.s4, bottom: TG.Space.s2, trailing: TG.Space.s4))
                .listRowBackground(Color.clear)
                .listRowSeparator(.hidden)
            content
        }
        .listStyle(.insetGrouped)
        .listSectionSpacing(TG.Space.s6)
        .scrollContentBackground(.hidden)
        .background(TG.Colors.bg)
        .contentMargins(.top, 0, for: .scrollContent)
    }
}

/// A list section headed by the design-system `SectionHeader`.
struct ShellSection<Content: View>: View {
    let title: String
    var count: Int?
    /// One quiet header action ("Show", "History").
    var action: String?
    var onAction: () -> Void = {}
    @ViewBuilder var content: Content

    var body: some View {
        Section {
            content.tgListRow()
        } header: {
            SectionHeader(title: title, count: count, action: action, onAction: onAction)
                .textCase(nil)
                .listRowInsets(EdgeInsets())
        }
    }
}

// MARK: - Row adapters (model → design-system row)

extension GroceryItemRow {
    init(item: GroceryItem, dates: RelativeDate, me: Person, onToggle: @escaping () -> Void) {
        self.init(
            name: item.name,
            qty: item.qty,
            note: item.note ?? item.addedBy.flatMap { $0 == me ? nil : "\($0.name) added" },
            done: item.done,
            by: item.boughtBy,
            when: item.viaReceipt ? "via receipt" : item.boughtAt.map { dates.past($0, midSentence: true) },
            me: me,
            onToggle: onToggle
        )
    }
}

extension TaskRow {
    init(task: TaskItem, dates: RelativeDate, me: Person, showSpace: SpaceKind? = nil, onToggle: @escaping () -> Void) {
        self.init(
            title: task.title,
            due: task.dueDate(calendar: dates.calendar).map(dates.due),
            dueIsUrgent: !task.done && (task.dueDate(calendar: dates.calendar).map(dates.isUrgent) ?? false),
            repeatText: task.repeatRule?.label,
            reminder: task.reminder.map { dates.reminder($0.remindAt) },
            assignee: task.space == .shared ? task.assignee.map(TaskAssignee.person) ?? .anyone : nil,
            done: task.done,
            doneBy: task.doneBy,
            showSpace: showSpace,
            me: me,
            onToggle: onToggle
        )
    }
}

extension NoteRow {
    init(note: Note, dates: RelativeDate, me: Person, showSpace: SpaceKind? = nil) {
        self.init(
            title: note.title.isEmpty ? "Untitled" : note.title,
            preview: note.body.split(separator: "\n").first.map(String.init),
            updated: dates.past(note.updatedAt),
            by: note.space == .shared ? note.updatedBy : nil,
            showSpace: showSpace,
            me: me
        )
    }
}
