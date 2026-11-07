import SwiftUI

/// Who a task is for, as the row shows it. `nil` on the row = no avatar slot (Personal tasks).
enum TaskAssignee: Hashable, Sendable {
    /// Anyone — the dashed ghost avatar.
    case anyone
    case person(Person)
}

/// A household task: check circle, title, and a wrapping metadata line — due date (warning tone for
/// today/overdue), repeat, reminder bell (hidden once done), "Sam did this", optional privacy badge.
struct TaskRow: View {
    let title: String
    var due: String?
    /// `warning` colour for today / overdue; the date text always carries the meaning too.
    var dueIsUrgent = false
    var repeatText: String?
    /// "Sat 9:00" — when the assignee will be reminded.
    var reminder: String?
    /// Shared tasks only.
    var assignee: TaskAssignee?
    var done = false
    var doneBy: Person?
    /// Adds a PrivacyBadge for this space (search, Home).
    var showSpace: SpaceKind?
    var me: Person = .alex
    var onToggle: () -> Void = {}

    private var hasMeta: Bool {
        due != nil || repeatText != nil || (reminder != nil && !done) || (done && doneBy != nil) || showSpace != nil
    }

    var body: some View {
        HStack(spacing: TG.Space.s3) {
            CheckCircle(checked: done, label: (done ? "Reopen " : "Complete ") + title, action: onToggle)

            VStack(alignment: .leading, spacing: DS.rowLineGap) {
                Text(title)
                    .font(TG.Font.body)
                    .foregroundStyle(done ? TG.Colors.ink2 : TG.Colors.ink)
                    .strikethrough(done, color: TG.Colors.ink3)
                    .lineLimit(2)

                if hasMeta {
                    FlowLayout(spacing: TG.Space.s2, lineSpacing: DS.rowLineGap) {
                        if let due {
                            meta(.calendar, due, a11y: "Due \(due)")
                                .foregroundStyle(dueIsUrgent ? TG.Colors.warning : TG.Colors.ink2)
                                .fontWeight(dueIsUrgent ? .medium : nil)
                        }
                        if let repeatText {
                            meta(.repeat, repeatText, a11y: "Repeats \(repeatText)")
                        }
                        if let reminder, !done {
                            meta(.bell, reminder, a11y: "Reminder \(reminder)")
                        }
                        if done, let doneBy {
                            Text("\(doneBy.displayName(me: me)) did this")
                        }
                        if let showSpace {
                            PrivacyBadge(space: showSpace)
                        }
                    }
                    .font(TG.Font.footnote)
                    .foregroundStyle(TG.Colors.ink2)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .alignmentGuide(.listRowSeparatorLeading) { $0[.leading] }
            .accessibilityElement(children: .combine)

            if let assignee {
                Group {
                    switch assignee {
                    case .anyone: Avatar(person: nil, size: 26).accessibilityLabel("Anyone")
                    case .person(let person): Avatar(person: person, size: 26)
                    }
                }
                .accessibilityLabel(assigneeLabel(assignee))
            }
        }
        .padding(.vertical, TG.Space.s3)
        .padding(.horizontal, TG.Space.s4)
        .frame(minHeight: DS.rowMinHeight)
    }

    private func meta(_ icon: IconName, _ text: String, a11y: String) -> some View {
        HStack(spacing: TG.Space.s1) {
            Icon(icon).imageScale(.small)
            Text(text)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(a11y)
    }

    private func assigneeLabel(_ assignee: TaskAssignee) -> String {
        switch assignee {
        case .anyone: "For anyone"
        case .person(let person): "For \(person == me ? "you" : person.name)"
        }
    }
}

// MARK: - Preview

struct TaskRowGallery: View {
    var body: some View {
        TGGroup {
            TaskRow(title: "Pay the internet bill", due: "Today", dueIsUrgent: true, repeatText: "Monthly",
                    reminder: "Today 9:00", assignee: .person(.alex))
            RowSeparator()
            TaskRow(title: "Replace the water filter", due: "Sat", repeatText: "Every 2 months", assignee: .anyone)
            RowSeparator()
            TaskRow(title: "Return the parcel", due: "Mon", reminder: "Mon 9:00", assignee: .person(.sam))
            RowSeparator()
            TaskRow(title: "Clean the bathroom", assignee: .person(.sam), done: true, doneBy: .sam)
            TaskRow(title: "Book a dentist appointment", due: "Next week", showSpace: .personal)
                .environment(\.space, .personal)
        }
        .padding(.vertical, TG.Space.s4)
        .frame(width: 390)
    }
}

#Preview("TaskRow · Light") { TaskRowGallery().catalogCanvas() }
#Preview("TaskRow · Dark") { TaskRowGallery().catalogCanvas().preferredColorScheme(.dark) }
