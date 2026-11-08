import SwiftUI

/// Home (HANDOFF §6.6): quick actions, an invite banner while Shared has one member, then three short
/// sections — Upcoming, Groceries (+ suggestions teaser), Recent notes. Lists, not dashboards: no statistics.
/// Everything comes from `store.home(in: space)`, shaped like `GET /v1/spaces/{id}/home`.
struct HomeScreen: View {
    @Environment(AppStore.self) private var store
    @Environment(ToastCenter.self) private var toasts
    @Environment(AppRouter.self) private var router
    @Environment(\.space) private var space
    @Environment(\.accent) private var accent
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    @State private var taskSheet: TaskSheet.Mode?
    @State private var showInvite = false

    var body: some View {
        TimelineView(.everyMinute) { _ in
            content(store.home(in: space), dates: store.dates)
        }
        .sheet(item: $taskSheet) { mode in
            switch mode {
            case .new:
                TaskSheet(mode: mode) { flows.create($0) }
            case .edit(let task):
                TaskSheet(mode: mode) { store.updateTask(task.id, in: space, with: $0) } onDelete: { flows.delete(task.id) }
            }
        }
        .sheet(isPresented: $showInvite) { InviteSheetPlaceholder() }
    }

    private var flows: TaskFlows { TaskFlows(store: store, toasts: toasts, space: space, reduceMotion: reduceMotion) }

    private func content(_ home: HomeSummary, dates: RelativeDate) -> some View {
        ShellList(subtitle: subtitle) {
            Section {
                quickActions
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                if home.showInvite {
                    inviteBanner
                        .listRowInsets(EdgeInsets(top: TG.Space.s4, leading: 0, bottom: 0, trailing: 0))
                        .listRowBackground(Color.clear)
                }
            }

            ShellSection(title: "Upcoming", count: home.tasks.total, action: "All tasks") { router.tab = .tasks } content: {
                if home.tasks.items.isEmpty {
                    quietRow("Nothing due. Enjoy the quiet.")
                }
                ForEach(home.tasks.items) { entry in
                    taskRow(entry, dates: dates)
                }
            }

            ShellSection(title: "Groceries", count: home.groceries.openCount, action: "Open list") { router.tab = .groceries } content: {
                if home.groceries.items.isEmpty {
                    quietRow("Nothing to buy")
                }
                ForEach(home.groceries.items) { entry in
                    GroceryItemRow(name: entry.name, qty: entry.qty, me: store.me) { markBought(entry) }
                        .contentShape(Rectangle())
                        .onTapGesture { router.tab = .groceries }
                }
                if let teaser = home.suggestionTeaser {
                    suggestionsTeaser(teaser)
                }
            }

            ShellSection(title: "Recent notes", action: "All notes") { router.tab = .notes } content: {
                if home.notes.isEmpty {
                    quietRow(space == .shared ? "No shared notes yet" : "No notes yet")
                }
                ForEach(home.notes) { entry in
                    NoteRow(
                        title: entry.title,
                        preview: entry.preview,
                        updated: dates.past(entry.updatedAt),
                        by: space == .shared ? entry.updatedBy : nil,
                        me: store.me
                    ) { router.open(entry.id) }
                }
            }
        }
    }

    // MARK: Pieces

    private var quickActions: some View {
        HStack(alignment: .top, spacing: TG.Space.s3) {
            quickAction("Item", icon: .cart, a11y: "Add grocery item") { router.addGrocery() }
            quickAction("Task", icon: .tasks, a11y: "New task") { taskSheet = .new }
            quickAction("Note", icon: .note, a11y: "New note") { router.open(store.createNote(in: space).id) }
        }
    }

    private func quickAction(_ title: String, icon: IconName, a11y: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: TG.Space.s3) {
                Icon(icon)
                    .font(TG.Font.title3)
                    .foregroundStyle(accent.ink)
                Text(title)
                    .font(TG.Font.subhead.weight(.semibold))
                    .foregroundStyle(TG.Colors.ink)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(TG.Space.s4)
            .background(TG.Colors.surface, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))
            .contentShape(Rectangle())
        }
        .buttonStyle(.bare)
        .accessibilityLabel(a11y)
    }

    private var inviteBanner: some View {
        HStack(spacing: TG.Space.s3) {
            Avatar(person: nil, size: 40)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: DS.rowLineGap) {
                Text("Shared works best with two")
                    .font(TG.Font.subhead.weight(.semibold))
                    .foregroundStyle(TG.Colors.ink)
                Text("Invite your partner to this space.")
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .combine)
            TGButton("Invite", size: .sm) { showInvite = true }
                .fixedSize()
        }
        .padding(TG.Space.s4)
        .background(TG.Colors.sharedSoft, in: RoundedRectangle(cornerRadius: TG.Radius.lg, style: .continuous))
    }

    private func taskRow(_ entry: HomeSummary.TaskEntry, dates: RelativeDate) -> some View {
        let due = entry.dueDay.map { $0.at(calendar: store.calendar) }
        return TaskRow(
            title: entry.title,
            due: due.map(dates.due),
            dueIsUrgent: entry.status == .overdue || entry.status == .today,
            repeatText: entry.repeatRule?.label,
            reminder: entry.reminderAt.map(dates.reminder),
            assignee: space == .shared ? entry.assignee.map(TaskAssignee.person) ?? .anyone : nil,
            me: store.me
        ) { flows.toggle(entry.id, done: false) }
            .contentShape(Rectangle())
            .onTapGesture {
                if let task = store.task(entry.id, in: space) { taskSheet = .edit(task) }
            }
            .accessibilityAction(named: "Edit") {
                if let task = store.task(entry.id, in: space) { taskSheet = .edit(task) }
            }
    }

    private func suggestionsTeaser(_ text: String) -> some View {
        Button { router.tab = .groceries } label: {
            HStack(spacing: TG.Space.s3) {
                Icon(.history).font(TG.Font.title3)
                Text(text)
                    .font(TG.Font.subhead.weight(.semibold))
                    .frame(maxWidth: .infinity, alignment: .leading)
                Icon(.chevron).font(TG.Font.footnote.weight(.semibold))
            }
            .foregroundStyle(accent.ink)
            .padding(.horizontal, TG.Space.s4)
            .frame(minHeight: DS.rowMinHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(.bare)
        .listRowBackground(accent.soft)
    }

    private func quietRow(_ text: String) -> some View {
        Text(text)
            .font(TG.Font.subhead)
            .foregroundStyle(TG.Colors.ink2)
            .padding(.horizontal, TG.Space.s4)
            .frame(maxWidth: .infinity, minHeight: DS.rowMinHeight, alignment: .leading)
    }

    private var subtitle: String {
        let now = store.now
        let hour = store.calendar.component(.hour, from: now)
        let greeting = hour < 12 ? "Good morning" : hour < 18 ? "Good afternoon" : "Good evening"
        return "\(store.dates.longDay(now)) · \(greeting), \(store.me.name)"
    }

    private func markBought(_ entry: HomeSummary.GroceryEntry) {
        let store = store, space = space
        withAnimation(.tg(.easeInOut(duration: 0.2), reduceMotion: reduceMotion)) {
            _ = store.markBought(entry.id, in: space)
        }
        toasts.showUndo("\(entry.name) bought") { store.unmarkBought(entry.id, in: space) }
    }
}

/// "Invite your partner" — the real invite (code + link) comes with accounts in phase 7.
struct InviteSheetPlaceholder: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: TG.Space.s4) {
            Icon(.people)
                .font(TG.Font.title2)
                .foregroundStyle(TG.Colors.sharedInk)
                .frame(width: 56, height: 56)
                .background(TG.Colors.sharedSoft, in: Circle())
                .accessibilityHidden(true)
            Text("Invite your partner")
                .font(TG.Font.title3.weight(.semibold))
                .foregroundStyle(TG.Colors.ink)
                .accessibilityAddTraits(.isHeader)
            Text("They’ll join your Shared space: groceries, household tasks and shared notes. Your Personal space stays private.")
                .font(TG.Font.subhead)
                .foregroundStyle(TG.Colors.ink2)
                .multilineTextAlignment(.center)
            Text("Invites open once accounts are set up.")
                .font(TG.Font.footnote)
                .foregroundStyle(TG.Colors.ink3)
            TGButton("Close", variant: .secondary, block: true) { dismiss() }
                .padding(.top, TG.Space.s2)
        }
        .padding(TG.Space.s5)
        .environment(\.space, .shared)
        .presentationDetents([.medium])
        .presentationDragIndicator(.visible)
        .presentationBackground(TG.Colors.surface)
    }
}
