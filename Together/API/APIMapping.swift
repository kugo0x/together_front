import Foundation

/// Server IDs behind the client's `SpaceKind`s, lists and people, learned from `/v1/spaces`, `/lists` and
/// `/members`. Everything the API sends is mapped to domain types through this.
struct ServerDirectory: Sendable {
    var spaceIDs: [SpaceKind: UUID] = [:]
    var defaultListIDs: [SpaceKind: UUID] = [:]
    var people: [UUID: Person] = [:]
    var me: Person

    init(me: Person) {
        self.me = me
        people[me.id] = me
    }

    func kind(of spaceID: UUID) -> SpaceKind? {
        spaceIDs.first { $0.value == spaceID }?.key
    }

    /// Someone we may not have listed yet (a former member) still gets a name.
    func person(_ id: UUID?) -> Person? {
        guard let id else { return nil }
        return people[id] ?? Person(id: id, name: "Someone", tint: id == me.id ? me.tint : .sam)
    }

    /// The owner gets the first identity colour, the partner the second — the same on both phones.
    static func people(from members: [MemberDTO]) -> [Person] {
        members.map { Person(id: $0.userId, name: $0.displayName, tint: $0.role == "owner" ? .alex : .sam) }
    }
}

enum APIMapping {
    // MARK: Groceries

    static func list(_ dto: GroceryListDTO, space: SpaceKind) -> GroceryList {
        GroceryList(id: dto.id, space: space, name: dto.name, isDefault: dto.isDefault)
    }

    static func item(_ dto: GroceryItemDTO, _ directory: ServerDirectory) -> GroceryItem {
        GroceryItem(id: dto.id, listID: dto.listId, name: dto.name, qty: dto.qty, note: dto.note,
                    addedBy: directory.person(dto.addedBy), done: dto.done, boughtBy: directory.person(dto.boughtBy),
                    boughtAt: dto.boughtAt, viaReceipt: dto.viaReceipt)
    }

    static func suggestion(_ dto: SuggestionDTO) -> Suggestion {
        Suggestion(name: dto.name, qty: dto.qty, reason: dto.reason)
    }

    static func trip(_ dto: TripDTO, space: SpaceKind, _ directory: ServerDirectory) -> Trip {
        Trip(
            id: dto.id, space: space, date: dto.shoppedAt,
            shoppers: dto.buyers.compactMap { directory.person($0) },
            itemCount: dto.itemCount,
            total: dto.totalGrosze.map(Money.decimal(grosze:)),
            merchant: dto.merchant,
            receiptImageID: dto.viaReceipt ? "receipt-\(dto.id.uuidString)" : nil,
            lines: (dto.lines ?? []).map {
                ReceiptLine(name: $0.name, qty: $0.qty, price: $0.priceGrosze.map(Money.decimal(grosze:)),
                            status: $0.onList == false ? .extra : .matched)
            }
        )
    }

    static func grosze(_ amount: Decimal?) -> Int? {
        amount.map { NSDecimalNumber(decimal: $0 * 100).rounding(accordingToBehavior: nil).intValue }
    }

    // MARK: Tasks

    static func task(_ dto: TaskDTO, space: SpaceKind, _ directory: ServerDirectory) -> TaskItem {
        let due = dto.due.flatMap { day($0.date) }
        var task = TaskItem(space: space, title: dto.title)
        task.id = dto.id
        task.notes = dto.notes
        task.dueDay = due
        task.repeatRule = dto.repeat.flatMap(RepeatRule.init(rawValue:))
        task.anchorDay = task.repeatRule == nil ? 0 : (due?.day ?? 0)
        task.assignee = space == .personal ? directory.me : directory.person(dto.assigneeId)
        task.reminder = dto.reminder.flatMap { reminder in
            guard reminder.status == "pending", let recipient = directory.person(reminder.recipientId) else { return nil }
            return TaskReminder(remindAt: reminder.remindAt, shiftedFrom: reminder.shiftedFrom, recipient: recipient)
        }
        task.createdBy = directory.person(dto.createdBy)
        task.done = dto.done
        task.doneBy = directory.person(dto.doneBy)
        task.doneAt = dto.doneAt
        task.lastDoneBy = directory.person(dto.lastDoneBy)
        task.lastDoneAt = dto.lastDoneAt
        return task
    }

    static func due(_ day: CalendarDay?) -> DueDTO? { day.map { DueDTO(date: $0.description, time: nil) } }

    /// "2026-11-09".
    static func day(_ text: String) -> CalendarDay? {
        let parts = text.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3 else { return nil }
        return CalendarDay(year: parts[0], month: parts[1], day: parts[2])
    }

    static func createBody(_ task: TaskItem, _ draft: AppStore.TaskDraft) -> CreateTaskBody {
        CreateTaskBody(
            title: task.title, notes: task.notes, due: due(task.dueDay), repeat: task.repeatRule?.rawValue,
            assigneeId: task.space == .shared ? task.assignee?.id : nil,
            reminder: task.reminder.map { ReminderInBody(at: $0.requested) }
        )
    }

    static func editBody(_ task: TaskItem) -> EditTaskBody {
        EditTaskBody(
            title: task.title, notes: task.notes, due: due(task.dueDay), repeat: task.repeatRule?.rawValue,
            assigneeId: task.assignee?.id, sendsAssignee: task.space == .shared,
            reminder: task.reminder.map { ReminderInBody(at: $0.requested) }
        )
    }

    // MARK: Notes

    static func note(_ dto: NoteDTO, space: SpaceKind, _ directory: ServerDirectory) -> Note {
        Note(
            id: dto.id, space: space, title: dto.title, body: dto.body,
            checklist: dto.items.sorted { ($0.position ?? 0) < ($1.position ?? 0) }.map {
                ChecklistItem(id: $0.id, label: $0.text, done: $0.done, doneBy: directory.person($0.doneBy), doneAt: $0.doneAt)
            },
            updatedAt: dto.updatedAt,
            updatedBy: directory.person(dto.updatedBy) ?? directory.me,
            createdBy: directory.person(dto.createdBy),
            version: dto.version
        )
    }

    // MARK: Me

    /// "22:00" → minutes after midnight.
    static func minutes(_ text: String?) -> Int? {
        guard let text else { return nil }
        let parts = text.split(separator: ":").compactMap { Int($0) }
        guard parts.count == 2 else { return nil }
        return parts[0] * 60 + parts[1]
    }

    static func quietHours(_ dto: QuietHoursDTO) -> QuietHours {
        QuietHours(start: minutes(dto.start) ?? QuietHours.default.start, end: minutes(dto.end) ?? QuietHours.default.end)
    }

    static func quietHoursDTO(_ quiet: QuietHours) -> QuietHoursDTO {
        QuietHoursDTO(start: String(format: "%02d:%02d", quiet.start / 60, quiet.start % 60),
                      end: String(format: "%02d:%02d", quiet.end / 60, quiet.end % 60))
    }

    static func prefs(_ dto: NotificationsDTO) -> NotificationPrefs {
        NotificationPrefs(taskReminders: dto.taskReminders ?? true, taskAssigned: dto.taskAssigned ?? true,
                          partnerJoined: dto.partnerJoined ?? true, groceryReminder: dto.groceryReminder ?? false)
    }

    static func prefsDTO(_ prefs: NotificationPrefs) -> NotificationsDTO {
        NotificationsDTO(taskReminders: prefs.taskReminders, taskAssigned: prefs.taskAssigned,
                         partnerJoined: prefs.partnerJoined, groceryReminder: prefs.groceryReminder)
    }

    /// API shopping day 0 = Sunday … 6; the store's is a `Calendar` weekday 1 = Sunday … 7.
    static func weekday(apiDay: Int?) -> Int? { apiDay.map { $0 + 1 } }
    static func apiDay(weekday: Int) -> Int { (weekday - 1 + 7) % 7 }

    static func user(_ dto: UserDTO) -> AuthUser {
        AuthUser(id: dto.id, email: dto.email, displayName: dto.displayName, providers: [])
    }

    static func user(_ dto: MeDTO) -> AuthUser {
        AuthUser(id: dto.id, email: dto.email, displayName: dto.displayName,
                 providers: dto.providers.compactMap(AuthProvider.init(rawValue:)))
    }

    static func tokens(_ dto: TokensDTO) -> AuthTokens {
        AuthTokens(accessToken: dto.accessToken, accessExpiresAt: dto.accessExpiresAt,
                   refreshToken: dto.refreshToken, refreshExpiresAt: dto.refreshExpiresAt)
    }
}
