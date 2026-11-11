import Foundation

/// Everything Home shows for ONE space — shaped like `GET /v1/spaces/{id}/home` (back/api/openapi.yaml, `Home`).
/// Today it's built from the in-memory store (`AppStore.home(in:)`); phase 9 decodes it from the API instead.
///
/// Three short sections, no statistics ("Lists, not dashboards"). Every section comes from this space only.
struct HomeSummary: Equatable, Sendable {
    struct Space: Equatable, Sendable {
        var kind: SpaceKind
        var name: String
        var memberCount: Int
    }

    struct TaskEntry: Equatable, Identifiable, Sendable {
        enum Status: String, Sendable { case overdue, today, upcoming, someday }

        var id: TaskItem.ID
        var title: String
        var dueDay: CalendarDay?
        var status: Status
        var assignee: Person?
        var assignedToMe: Bool
        var repeatRule: RepeatRule?
        var reminderAt: Date?
    }

    struct Tasks: Equatable, Sendable {
        /// Open tasks in the space ("5 to do").
        var total: Int
        /// Up to 3 that need attention.
        var items: [TaskEntry]
    }

    struct GroceryEntry: Equatable, Identifiable, Sendable {
        var id: GroceryItem.ID
        var name: String
        var qty: String?
    }

    struct Groceries: Equatable, Sendable {
        var listID: GroceryList.ID
        var openCount: Int
        /// The newest 3 items to buy.
        var items: [GroceryEntry]
        /// Names for "3 things you usually buy — review"; empty when suggestions are off.
        var suggestions: [String]
    }

    struct NoteEntry: Equatable, Identifiable, Sendable {
        var id: Note.ID
        var title: String
        var preview: String?
        var updatedAt: Date
        var updatedBy: Person?
    }

    var space: Space
    /// "Invite your partner" — a Shared space with nobody else in it.
    var showInvite: Bool
    var tasks: Tasks
    var groceries: Groceries
    /// The 3 most recently updated notes.
    var notes: [NoteEntry]

    static let maxItems = 3

    /// "3 things you usually buy — review".
    var suggestionTeaser: String? {
        let n = groceries.suggestions.count
        guard n > 0 else { return nil }
        return "\(n) \(n == 1 ? "thing" : "things") you usually buy — review"
    }
}

extension AppStore {
    /// The Home summary for a space, as the API would return it. Swap this for the network call in phase 9.
    func home(in space: SpaceKind) -> HomeSummary {
        let today = today
        let active = activeTasks(in: space) // by due date, undated last

        func status(_ task: TaskItem) -> HomeSummary.TaskEntry.Status {
            guard let due = task.dueDay else { return .someday }
            return due < today ? .overdue : due == today ? .today : .upcoming
        }
        func isMine(_ task: TaskItem) -> Bool { space == .personal || task.assignee == me }
        // overdue → due today → assigned to me → by date (the active list is already by date).
        func rank(_ task: TaskItem) -> Int {
            switch status(task) {
            case .overdue: 0
            case .today: 1
            default: isMine(task) ? 2 : 3
            }
        }
        let needingAttention = active.enumerated()
            .sorted { (rank($0.element), $0.offset) < (rank($1.element), $1.offset) }
            .prefix(HomeSummary.maxItems)
            .map(\.element)

        let list = defaultList(for: space)
        let toBuy = toBuy(in: space)

        return HomeSummary(
            space: .init(
                kind: space,
                name: space.displayName,
                memberCount: space == .personal ? 1 : (partner == nil ? 1 : 2)
            ),
            showInvite: space == .shared && partner == nil,
            tasks: .init(
                total: active.count,
                items: needingAttention.map { task in
                    .init(
                        id: task.id, title: task.title, dueDay: task.dueDay, status: status(task),
                        assignee: task.assignee, assignedToMe: isMine(task),
                        repeatRule: task.repeatRule, reminderAt: task.reminder?.remindAt
                    )
                }
            ),
            groceries: .init(
                listID: list.id,
                openCount: toBuy.count,
                items: toBuy.prefix(HomeSummary.maxItems).map { .init(id: $0.id, name: $0.name, qty: $0.qty) },
                suggestions: suggestions(in: space).map(\.name)
            ),
            notes: notes(in: space).prefix(HomeSummary.maxItems).map {
                .init(id: $0.id, title: $0.displayTitle, preview: $0.preview, updatedAt: $0.updatedAt, updatedBy: $0.updatedBy)
            }
        )
    }
}
