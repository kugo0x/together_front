import Foundation

// Wire models of back/api/openapi.yaml (0.8.0), one per schema, named `<Schema>DTO`. Keys are camelCase here and
// snake_case on the wire (`APICoding`). `TogetherTests/APISpecTests` checks them against the spec: every schema's
// synthesized example decodes, and every request body only uses properties the schema has (the API rejects
// unknown fields). Domain types (`GroceryItem`, `TaskItem`, …) are built from these in `APIMapping`.

// MARK: Auth & profile

struct UserDTO: Codable, Sendable {
    var id: UUID
    var email: String?
    var emailVerified: Bool
    var displayName: String
    var createdAt: Date
}

struct QuietHoursDTO: Codable, Equatable, Sendable {
    var start: String?
    var end: String?
}

struct AvatarDTO: Codable, Sendable {
    var url: String?
    var updatedAt: Date?
}

struct MeDTO: Codable, Sendable {
    var id: UUID
    var email: String?
    var emailVerified: Bool
    var displayName: String
    var createdAt: Date
    var providers: [String]
    var timeZone: String
    var quietHours: QuietHoursDTO
    var avatar: AvatarDTO?
}

struct TokensDTO: Codable, Sendable {
    var accessToken: String
    var tokenType: String
    var expiresIn: Int
    var accessExpiresAt: Date
    var refreshToken: String
    var refreshExpiresAt: Date
}

struct AuthResultDTO: Codable, Sendable {
    var user: UserDTO
    var tokens: TokensDTO
    var isNewUser: Bool
}

struct RegisterBody: Encodable, Sendable {
    var email: String
    var password: String
    var displayName: String?
}

struct LoginBody: Encodable, Sendable {
    var email: String
    var password: String
}

struct IDTokenBody: Encodable, Sendable {
    var idToken: String
    var nonce: String
    var displayName: String?
}

struct RefreshBody: Encodable, Sendable { var refreshToken: String }
struct EmailBody: Encodable, Sendable { var email: String }

struct MePatchBody: Encodable, Sendable {
    var displayName: String?
    var timeZone: String?
    var quietHours: QuietHoursDTO?
}

struct NotificationsDTO: Codable, Equatable, Sendable {
    var taskReminders: Bool?
    var taskAssigned: Bool?
    var partnerJoined: Bool?
    var groceryReminder: Bool?
}

struct SettingsDTO: Codable, Sendable {
    var timeZone: String
    var quietHours: QuietHoursDTO
    var suggestionsEnabled: Bool
    var notifications: NotificationsDTO
}

struct SettingsPatchBody: Encodable, Sendable {
    var timeZone: String?
    var quietHours: QuietHoursDTO?
    var suggestionsEnabled: Bool?
    var notifications: NotificationsDTO?
}

struct DeviceDTO: Codable, Sendable {
    var id: UUID?
    var platform: String?
    var token: String?
    var environment: String?
    var createdAt: Date?
    var lastSeenAt: Date?
}

struct DeviceBody: Encodable, Sendable {
    var token: String
    var platform = "ios"
    var environment: String
}

// MARK: Spaces & invites

struct SpaceDTO: Codable, Sendable {
    var id: UUID
    var kind: String
    var name: String
    var ownerId: UUID?
    var createdAt: Date
    var role: String?
    var memberCount: Int?
    var shoppingDay: Int?
}

struct SpacesDTO: Codable, Sendable { var spaces: [SpaceDTO] }

/// PATCH /v1/spaces/{id} — merge patch: `shopping_day: null` clears it, so it is always sent.
struct SpacePatchBody: Encodable, Sendable {
    var shoppingDay: Int?

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(shoppingDay, forKey: .shoppingDay)
    }

    enum CodingKeys: String, CodingKey { case shoppingDay }
}

struct CreateSpaceBody: Encodable, Sendable {
    var kind = "shared"
}

struct MemberDTO: Codable, Sendable {
    var userId: UUID
    var displayName: String
    var role: String
    var joinedAt: Date
    var avatar: AvatarDTO?
}

struct MembersDTO: Codable, Sendable { var members: [MemberDTO] }

struct InviteDTO: Codable, Sendable {
    var id: UUID
    var spaceId: UUID
    var code: String
    var link: String
    var status: String
    var createdBy: UUID?
    var expiresAt: Date
    var createdAt: Date
}

struct InvitePreviewDTO: Codable, Sendable {
    struct SpaceRef: Codable, Sendable { var id: UUID?; var name: String? }
    struct Inviter: Codable, Sendable { var id: UUID?; var displayName: String? }
    var code: String
    var status: String
    var expiresAt: Date
    var space: SpaceRef
    var inviter: Inviter?
}

struct AcceptInviteDTO: Codable, Sendable { var space: SpaceDTO? }

// MARK: Groceries

struct GroceryListDTO: Codable, Sendable {
    var id: UUID
    var spaceId: UUID
    var name: String
    var isDefault: Bool
    var openCount: Int?
    var boughtCount: Int?
    var createdAt: Date
    var updatedAt: Date
}

struct ListsDTO: Codable, Sendable { var lists: [GroceryListDTO] }

struct GroceryItemDTO: Codable, Sendable {
    var id: UUID
    var listId: UUID
    var spaceId: UUID
    var name: String
    var qty: String?
    var note: String?
    var addedBy: UUID?
    var done: Bool
    var boughtBy: UUID?
    var boughtAt: Date?
    var viaReceipt: Bool
    var createdAt: Date
    var updatedAt: Date
}

struct ListWithItemsDTO: Codable, Sendable {
    var list: GroceryListDTO
    var items: [GroceryItemDTO]
}

struct ItemsDTO: Codable, Sendable { var items: [GroceryItemDTO] }

/// POST …/items — `text` is the quick-add field, parsed by the server like the client's QuantityParser.
struct AddItemBody: Encodable, Sendable {
    var text: String?
    var name: String?
    var qty: String?
    var note: String?
}

/// PATCH …/items/{id} — an empty qty/note clears it, so both are always sent.
struct EditItemBody: Encodable, Sendable {
    var name: String
    var qty: String
    var note: String
}

struct PurchaseDTO: Codable, Sendable {
    var id: UUID?
    var itemId: UUID?
    var name: String
    var qty: String?
    var priceGrosze: Int?
    var boughtBy: UUID?
    var boughtAt: Date?
    var viaReceipt: Bool?
    var onList: Bool?
}

struct TripDTO: Codable, Sendable {
    var id: UUID
    var spaceId: UUID
    var shoppedAt: Date
    var totalGrosze: Int?
    var merchant: String?
    var viaReceipt: Bool
    var createdBy: UUID?
    var itemCount: Int
    var buyers: [UUID]
    var lines: [PurchaseDTO]?
}

struct MonthSummaryDTO: Codable, Sendable {
    var month: String
    var totalGrosze: Int
    var trips: Int
    var tripsWithTotal: Int
}

struct TripsPageDTO: Codable, Sendable {
    var month: MonthSummaryDTO?
    var previousMonth: MonthSummaryDTO?
    var trips: [TripDTO]
}

struct SuggestionDTO: Codable, Sendable {
    var name: String
    var qty: String?
    var reason: String
    var intervalDays: Int
    var timesBought: Int
    var lastBoughtAt: Date
}

struct SuggestionsDTO: Codable, Sendable { var suggestions: [SuggestionDTO] }
struct DismissSuggestionBody: Encodable, Sendable { var name: String }
struct AcceptSuggestionsBody: Encodable, Sendable { var names: [String] }

struct ReceiptLineInBody: Encodable, Sendable {
    var name: String
    var qty: String?
    var priceGrosze: Int?
    var itemId: UUID?
    var purchaseId: UUID?
}

struct ConfirmReceiptBody: Encodable, Sendable {
    var lines: [ReceiptLineInBody]
    var totalGrosze: Int?
    var merchant: String?
    var shoppedAt: Date?
}

struct ConfirmReceiptDTO: Codable, Sendable {
    var trip: TripDTO
    var bought: [GroceryItemDTO]?
}

// MARK: Tasks

struct DueDTO: Codable, Equatable, Sendable {
    /// "2026-11-09".
    var date: String
    /// "18:00"; `nil` = all day (the MVP UI has no time).
    var time: String?
}

struct ReminderDTO: Codable, Sendable {
    var remindAt: Date
    var shiftedFrom: Date?
    var recipientId: UUID
    var status: String
}

struct TaskDTO: Codable, Sendable {
    var id: UUID
    var spaceId: UUID
    var title: String
    var notes: String?
    var due: DueDTO?
    var timeZone: String
    var `repeat`: String?
    var assigneeId: UUID?
    var createdBy: UUID?
    var done: Bool
    var doneAt: Date?
    var doneBy: UUID?
    var lastDoneAt: Date?
    var lastDoneBy: UUID?
    var reminder: ReminderDTO?
    var createdAt: Date
    var updatedAt: Date
}

struct TasksDTO: Codable, Sendable { var tasks: [TaskDTO] }

struct CompleteTaskDTO: Codable, Sendable {
    var task: TaskDTO
    var rolled: Bool?
}

struct ReminderInBody: Codable, Sendable { var at: Date }

/// POST /tasks.
struct CreateTaskBody: Encodable, Sendable {
    var title: String
    var notes: String?
    var due: DueDTO?
    var `repeat`: String?
    var assigneeId: UUID?
    var reminder: ReminderInBody?
}

/// PATCH /tasks/{id} — a JSON merge patch with every field the sheet edits; `null` clears. `assigneeId` is left out
/// for Personal tasks (always the owner's).
struct EditTaskBody: Encodable, Sendable {
    var title: String
    var notes: String?
    var due: DueDTO?
    var `repeat`: String?
    var assigneeId: UUID?
    var sendsAssignee: Bool
    var reminder: ReminderInBody?

    enum CodingKeys: String, CodingKey { case title, notes, due, `repeat`, assigneeId, reminder }

    func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        try c.encode(title, forKey: .title)
        try c.encode(notes, forKey: .notes)
        try c.encode(due, forKey: .due)
        try c.encode(`repeat`, forKey: .repeat)
        if sendsAssignee { try c.encode(assigneeId, forKey: .assigneeId) }
        try c.encode(reminder, forKey: .reminder)
    }
}

// MARK: Notes

struct NoteItemDTO: Codable, Sendable {
    var id: UUID
    var position: Int?
    var text: String
    var done: Bool
    var doneBy: UUID?
    var doneAt: Date?
    var updatedAt: Date?
    var updatedBy: UUID?
}

struct NoteDTO: Codable, Sendable {
    var id: UUID
    var spaceId: UUID
    var title: String
    var body: String
    var preview: String
    var version: Int
    var items: [NoteItemDTO]
    var itemCount: Int
    var doneCount: Int
    var createdBy: UUID?
    var createdAt: Date
    var updatedBy: UUID?
    var updatedAt: Date
}

struct NotesDTO: Codable, Sendable { var notes: [NoteDTO] }

struct CreateNoteBody: Encodable, Sendable {
    var title: String
    var body: String
    var items: [String]
}

struct EditNoteBody: Encodable, Sendable {
    var title: String
    var body: String
}

/// 409 `version_conflict` carries the note as it is now.
struct NoteConflictDTO: Codable, Sendable { var note: NoteDTO? }

struct DeleteNoteDTO: Codable, Sendable { var restoreUntil: Date? }

struct MoveNoteBody: Encodable, Sendable { var spaceId: UUID }

struct MoveNoteDTO: Codable, Sendable {
    struct Undo: Codable, Sendable { var spaceId: UUID?; var until: Date? }
    var note: NoteDTO
    var undo: Undo?
}

struct AddNoteItemBody: Encodable, Sendable {
    var text: String
    var position: Int?
}

struct EditNoteItemBody: Encodable, Sendable {
    var text: String?
    var done: Bool?
    var position: Int?
}

// MARK: Home

struct HomeDTO: Codable, Sendable {
    struct SpaceRef: Codable, Sendable { var id: UUID?; var kind: String?; var name: String?; var memberCount: Int? }
    struct TaskRef: Codable, Sendable {
        var id: UUID?; var title: String?; var due: DueDTO?; var status: String?
        var assigneeId: UUID?; var assignedToMe: Bool?; var `repeat`: String?; var reminderAt: Date?
    }
    struct Tasks: Codable, Sendable { var total: Int?; var items: [TaskRef]? }
    struct ItemRef: Codable, Sendable { var id: UUID?; var name: String?; var qty: String? }
    struct Groceries: Codable, Sendable { var listId: UUID?; var openCount: Int?; var items: [ItemRef]?; var suggestions: [String]? }
    struct NoteRef: Codable, Sendable { var id: UUID?; var title: String?; var preview: String?; var updatedAt: Date?; var updatedBy: UUID? }
    struct Notes: Codable, Sendable { var items: [NoteRef]? }
    var space: SpaceRef
    var showInvite: Bool
    var tasks: Tasks
    var groceries: Groceries
    var notes: Notes
}

// MARK: Events (GET /v1/spaces/{id}/events)

/// One `data:` payload of the space stream: GroceryEvent, TaskEvent, NoteEvent or MemberJoinedEvent.
struct SpaceEventDTO: Codable, Sendable {
    struct JoinedMember: Codable, Sendable { var userId: UUID; var displayName: String }
    var type: String
    var spaceId: UUID
    var actorId: UUID
    var at: Date
    var list: GroceryListDTO?
    var item: GroceryItemDTO?
    var trip: TripDTO?
    var task: TaskDTO?
    var note: NoteDTO?
    var member: JoinedMember?
    var removedId: UUID?
}
