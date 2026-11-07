import Foundation

// Client data model (HANDOFF §4) plus the product decisions in ../CLAUDE.md:
// grocery items belong to a `GroceryList` (one default list per space in the MVP UI),
// tasks have an optional description (`notes`), one reminder per task.
//
// People are `Person` values for now; the real app swaps them for user IDs in phase 9.

extension SpaceKind: CaseIterable, Identifiable {
    static var allCases: [SpaceKind] { [.shared, .personal] }
    var id: String { rawValue }
}

/// A grocery list. The API supports many per space; the MVP UI only shows the default one.
struct GroceryList: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var space: SpaceKind
    var name: String = "Groceries"
    var isDefault: Bool = true
}

/// An item on a grocery list. Its space comes from the list — there is no separate `space` field to drift.
struct GroceryItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var listID: GroceryList.ID
    var name: String
    var qty: String?
    var note: String?
    var done: Bool = false
    var boughtBy: Person?
    var boughtAt: Date?
    var viaReceipt: Bool = false
}

enum RepeatRule: String, Codable, CaseIterable, Sendable {
    case weekly, monthly, everyTwoMonths

    var label: String {
        switch self {
        case .weekly: "Weekly"
        case .monthly: "Monthly"
        case .everyTwoMonths: "Every 2 months"
        }
    }
}

struct TaskItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var space: SpaceKind
    var title: String
    /// Optional description, shown in the task sheet.
    var notes: String?
    var due: Date?
    var repeatRule: RepeatRule?
    /// Shared tasks only; `nil` = anyone.
    var assignee: Person?
    /// One reminder per task, assigned tasks only.
    var reminderAt: Date?
    var done: Bool = false
    var doneBy: Person?
}

struct ChecklistItem: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var label: String
    var done: Bool = false
}

/// Plain-text body plus a checklist; no formatting in the MVP.
struct Note: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var space: SpaceKind
    var title: String
    var body: String
    var checklist: [ChecklistItem] = []
    var updatedAt: Date
    var updatedBy: Person
}

struct ReceiptLine: Identifiable, Codable, Hashable, Sendable {
    enum Status: String, Codable, Sendable { case matched, extra, unclear }

    var id: UUID = UUID()
    var name: String
    var qty: String?
    var price: Decimal
    var status: Status
    var included: Bool = true
}

/// A shopping trip in History. Money appears only as trip totals and one month line.
struct Trip: Identifiable, Codable, Hashable, Sendable {
    var id: UUID = UUID()
    var space: SpaceKind
    var date: Date
    var shoppers: [Person]
    var itemCount: Int
    var total: Decimal?
    var receiptImageID: String?
    var lines: [ReceiptLine] = []
}
