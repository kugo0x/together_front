import SwiftUI

/// New / edit task. Only the title is required; who, when, repeat and the reminder are chips revealed once
/// there is a title (design/prototype NewTask + TaskReminder, `remindOptions` / `reminderFor`).
///
/// Reminders exist only when someone is assigned (Me / partner — never Anyone; Personal tasks are always
/// mine), one per task. A time inside the receiver's quiet hours shows a warning and is saved as 8:00.
struct TaskSheet: View {
    enum Mode: Identifiable {
        case new
        case edit(TaskItem)

        var id: String {
            switch self {
            case .new: "new"
            case .edit(let task): task.id.uuidString
            }
        }
    }

    enum ReminderChoice: Hashable {
        /// One of `ReminderPlanner.options`.
        case option(Int)
        /// "Pick time" on the due day.
        case custom
        /// The time an existing reminder was set for, kept as it is until changed.
        case existing(Date)
        case off
    }

    let mode: Mode
    let onSave: (AppStore.TaskDraft) -> Void
    var onDelete: (() -> Void)?

    @Environment(AppStore.self) private var store
    @Environment(\.space) private var space
    @Environment(\.accent) private var accent
    @Environment(\.dismiss) private var dismiss

    @State private var title: String
    @State private var notes: String
    @State private var dueDay: CalendarDay?
    @State private var repeatRule: RepeatRule?
    @State private var assignee: Person?
    @State private var reminderChoice: ReminderChoice
    @State private var customTime: Date
    @State private var pickingDate = false
    @FocusState private var titleFocused: Bool

    init(mode: Mode, onSave: @escaping (AppStore.TaskDraft) -> Void, onDelete: (() -> Void)? = nil) {
        self.mode = mode
        self.onSave = onSave
        self.onDelete = onDelete
        let task: TaskItem? = if case .edit(let t) = mode { t } else { nil }
        _title = State(initialValue: task?.title ?? "")
        _notes = State(initialValue: task?.notes ?? "")
        _dueDay = State(initialValue: task?.dueDay)
        _repeatRule = State(initialValue: task?.repeatRule)
        _assignee = State(initialValue: task?.assignee)
        _reminderChoice = State(initialValue: task.map { $0.reminder.map { .existing($0.requested) } ?? .off } ?? .option(0))
        var evening = DateComponents()
        evening.hour = 20
        _customTime = State(initialValue: Calendar.current.date(from: evening) ?? .now)
    }

    private var isNew: Bool { if case .new = mode { true } else { false } }
    private var hasTitle: Bool { !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var dates: RelativeDate { store.dates }
    private var calendar: Calendar { store.calendar }
    private var recipient: Person? { store.reminderRecipient(assignee: assignee, in: space) }
    private var options: [ReminderOption] { ReminderPlanner.options(due: dueDay, now: store.now, calendar: calendar) }

    /// The time asked for, before quiet hours.
    private var requestedReminder: Date? {
        guard recipient != nil else { return nil }
        switch reminderChoice {
        case .option(let i): return options.indices.contains(i) ? options[i].at : nil
        case .custom: return ReminderPlanner.custom(TimeOfDay(customTime, calendar: calendar), due: dueDay, now: store.now, calendar: calendar)
        case .existing(let date): return date
        case .off: return nil
        }
    }

    private var planned: TaskReminder? {
        guard let recipient, let requested = requestedReminder else { return nil }
        return store.planReminder(at: requested, for: recipient)
    }

    private var draft: AppStore.TaskDraft {
        AppStore.TaskDraft(
            title: title,
            notes: notes,
            dueDay: dueDay,
            repeatRule: dueDay == nil ? nil : repeatRule,
            assignee: assignee,
            reminderAt: requestedReminder
        )
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: TG.Space.s5) {
                    PrivacyBadge(space: space)
                    titleField
                    if hasTitle || !isNew {
                        if space == .shared { whoSection }
                        whenSection
                        if dueDay != nil { repeatSection }
                        if recipient != nil { reminderSection }
                        notesField
                    }
                    actions
                }
                .padding(TG.Space.s5)
                .animation(.easeInOut(duration: 0.2), value: hasTitle)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(TG.Colors.surface)
            .navigationTitle(isNew ? "New task" : "Edit task")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .tint(accent.ink)
        .presentationDetents([.large])
        .onAppear { if isNew { titleFocused = true } }
    }

    // MARK: Sections

    private var titleField: some View {
        TextField("Task title", text: $title, prompt: Text("What needs doing?").foregroundStyle(TG.Colors.ink2), axis: .vertical)
            .lineLimit(1...3)
            .font(TG.Font.body)
            .foregroundStyle(TG.Colors.ink)
            .focused($titleFocused)
            .submitLabel(.done)
            .padding(.horizontal, TG.Space.s4)
            .padding(.vertical, TG.Space.s3)
            .background(TG.Colors.surface2, in: RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))
            .accessibilityLabel("Task title")
    }

    private var whoSection: some View {
        chipSection("Who") {
            Chip("Anyone", selected: assignee == nil) { assignee = nil }
            Chip("Me", selected: assignee == store.me) { assignee = store.me }
            if let partner = store.partner {
                Chip(partner.name, selected: assignee == partner) { assignee = partner }
            }
        }
    }

    private var whenSection: some View {
        let today = store.today
        let presets: [(String, CalendarDay)] = [("Today", today), ("Tomorrow", today.adding(days: 1))]
            + [7, 2].compactMap { weekday -> (String, CalendarDay)? in
                let day = nextWeekday(weekday, after: today)
                return today.days(until: day) > 1 ? (weekdayName(day), day) : nil
            }
        let isPreset = dueDay == nil || presets.contains { $0.1 == dueDay }
        return VStack(alignment: .leading, spacing: TG.Space.s2) {
            chipSection("When") {
                Chip("No date", selected: dueDay == nil) { setDue(nil) }
                ForEach(presets, id: \.1) { label, day in
                    Chip(label, selected: dueDay == day) { setDue(day) }
                }
                Chip(isPreset ? "Pick date" : dates.due(dueDay!.at(calendar: calendar)), icon: .calendar, selected: !isPreset || pickingDate) {
                    pickingDate.toggle()
                    if pickingDate, dueDay == nil { setDue(today) }
                }
            }
            if pickingDate {
                DatePicker(
                    "Date",
                    selection: Binding(
                        get: { (dueDay ?? today).at(hour: 12, calendar: calendar) },
                        set: { setDue(CalendarDay($0, calendar: calendar)) }
                    ),
                    in: today.at(calendar: calendar)...,
                    displayedComponents: .date
                )
                .datePickerStyle(.graphical)
                .tint(accent.fill)
            }
        }
    }

    private var repeatSection: some View {
        chipSection("Repeat") {
            Chip("Never", selected: repeatRule == nil) { repeatRule = nil }
            ForEach(RepeatRule.allCases, id: \.self) { rule in
                Chip(rule.label, selected: repeatRule == rule) { repeatRule = rule }
            }
        }
    }

    private var reminderSection: some View {
        VStack(alignment: .leading, spacing: TG.Space.s3) {
            TG.Colors.separator.frame(height: DS.hairline)
            chipSection(recipient == store.me ? "Remind me" : "Remind \(recipient?.name ?? "")") {
                if case .existing(let date) = reminderChoice {
                    Chip(dates.reminder(date), icon: .bell, selected: true) {}
                }
                ForEach(Array(options.enumerated()), id: \.offset) { i, option in
                    Chip(option.label, selected: reminderChoice == .option(i)) { reminderChoice = .option(i) }
                }
                Chip("Pick time", selected: reminderChoice == .custom) { reminderChoice = .custom }
                Chip("Off", selected: reminderChoice == .off) { reminderChoice = .off }
            }
            if reminderChoice == .custom {
                DatePicker("Time", selection: $customTime, displayedComponents: .hourAndMinute)
                    .font(TG.Font.subhead)
                    .padding(.horizontal, TG.Space.s3)
                    .padding(.vertical, TG.Space.s2)
                    .background(TG.Colors.surface2, in: RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))
            }
            if let planned, let recipient {
                if planned.shiftedFrom != nil {
                    let quiet = (store.quietHours[recipient] ?? .default)
                    Text((recipient == store.me ? "That’s in your quiet hours" : "That’s in \(recipient.name)’s quiet hours")
                         + " (\(quiet.text)). It will arrive at \(TimeOfDay(planned.remindAt, calendar: calendar).text).")
                        .font(TG.Font.footnote.weight(.medium))
                        .foregroundStyle(TG.Colors.warning)
                }
                VStack(alignment: .leading, spacing: TG.Space.s2) {
                    Text((recipient == store.me ? "You’ll get this · " : "\(recipient.name) will get this · ")
                         + dates.reminder(planned.remindAt))
                        .font(TG.Font.caption)
                        .foregroundStyle(TG.Colors.ink2)
                    NotificationPreview(
                        title: ReminderText.title(setBy: createdBy, recipient: recipient),
                        message: previewMessage,
                        when: TimeOfDay(planned.remindAt, calendar: calendar).text
                    )
                }
            }
        }
    }

    private var notesField: some View {
        VStack(alignment: .leading, spacing: TG.Space.s2) {
            sectionLabel("Details")
            TextField("Details", text: $notes, prompt: Text("Add details (optional)").foregroundStyle(TG.Colors.ink3), axis: .vertical)
                .lineLimit(2...6)
                .font(TG.Font.body)
                .foregroundStyle(TG.Colors.ink)
                .padding(.horizontal, TG.Space.s4)
                .padding(.vertical, TG.Space.s3)
                .background(TG.Colors.surface2, in: RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))
        }
    }

    private var actions: some View {
        VStack(spacing: TG.Space.s3) {
            TGButton(isNew ? "Add task" : "Save", icon: isNew ? .plus : nil, block: true) {
                onSave(draft)
                dismiss()
            }
            .disabled(!hasTitle)
            .opacity(hasTitle ? 1 : DS.disabledOpacity)
            if let onDelete {
                TGButton("Delete task", icon: .trash, variant: .destructive, block: true) {
                    dismiss()
                    onDelete()
                }
            }
        }
        .padding(.top, TG.Space.s2)
    }

    // MARK: Helpers

    private var createdBy: Person {
        if case .edit(let task) = mode, let by = task.createdBy { return by }
        return store.me
    }

    private var previewMessage: String {
        let name = hasTitle ? title.trimmingCharacters(in: .whitespacesAndNewlines) : "Your task"
        guard let dueDay else { return name }
        return name + " · " + ReminderText.dueLabel(dueDay, today: store.today)
    }

    private func setDue(_ day: CalendarDay?) {
        dueDay = day
        if day == nil { pickingDate = false }
        switch reminderChoice {
        case .option, .existing: reminderChoice = .option(0)
        case .custom, .off: break
        }
    }

    private func nextWeekday(_ weekday: Int, after day: CalendarDay) -> CalendarDay {
        let ahead = (weekday - day.weekday + 7) % 7
        return day.adding(days: ahead == 0 ? 7 : ahead)
    }

    private func weekdayName(_ day: CalendarDay) -> String {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_GB")
        return c.weekdaySymbols[day.weekday - 1]
    }

    private func sectionLabel(_ text: String) -> some View {
        Text(text)
            .font(TG.Font.footnote.weight(.semibold))
            .foregroundStyle(TG.Colors.ink2)
            .accessibilityAddTraits(.isHeader)
    }

    /// A labelled single-line row of chips that scrolls sideways (chips never stack two rows deep).
    private func chipSection<Chips: View>(_ label: String, @ViewBuilder chips: () -> Chips) -> some View {
        VStack(alignment: .leading, spacing: TG.Space.s2) {
            sectionLabel(label)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: TG.Space.s2) { chips() }
                    .padding(.horizontal, TG.Space.s5)
            }
            .padding(.horizontal, -TG.Space.s5)
        }
    }
}
