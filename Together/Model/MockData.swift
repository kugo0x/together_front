import Foundation

/// Seed data copied from the `constructor` in design/prototype/Main.dc.html.
///
/// The prototype uses display strings ("Sat", "Yesterday"); here they are real dates relative to `now`,
/// so the app looks the same whatever day it is launched. The prototype's "today" is Saturday, 7 November.
struct MockData: Sendable {
    var lists: [GroceryList]
    var groceries: [GroceryItem]
    var suggestions: [SpaceKind: [Suggestion]]
    var tasks: [TaskItem]
    var notes: [Note]
    var trips: [Trip]
    /// The sample receipt used by the receipt flow (phase 8).
    var receipt: [ReceiptLine]

    static func make(now: Date = .now, calendar: Calendar = .current) -> MockData {
        let today = calendar.startOfDay(for: now)
        func day(_ offset: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
            let d = calendar.date(byAdding: .day, value: offset, to: today)!
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: d)!
        }
        func ago(hours: Int) -> Date { calendar.date(byAdding: .hour, value: -hours, to: now)! }
        func pln(_ s: String) -> Decimal { Decimal(string: s)! }

        let shared = GroceryList(space: .shared)
        let personal = GroceryList(space: .personal)

        let groceries: [GroceryItem] = [
            .init(listID: shared.id, name: "Oat milk", qty: "2", addedBy: .sam),
            .init(listID: shared.id, name: "Tomatoes", qty: "1 kg"),
            .init(listID: shared.id, name: "Sourdough bread"),
            .init(listID: shared.id, name: "Greek yogurt", qty: "2"),
            .init(listID: shared.id, name: "Spinach", note: "For Sunday’s pasta"),
            .init(listID: shared.id, name: "Chicken thighs", qty: "1 kg"),
            .init(listID: shared.id, name: "Lemons", qty: "3", addedBy: .sam),
            .init(listID: shared.id, name: "Pasta", done: true, boughtBy: .sam, boughtAt: day(-1, 18)),
            .init(listID: shared.id, name: "Olive oil", done: true, boughtBy: .alex, boughtAt: day(-1, 18)),
            .init(listID: personal.id, name: "Protein bars", qty: "6"),
            .init(listID: personal.id, name: "Razor blades"),
            .init(listID: personal.id, name: "Birthday card for Sam"),
        ]

        func cday(_ offset: Int) -> CalendarDay { CalendarDay(day(offset), calendar: calendar) }
        func task(
            _ space: SpaceKind, _ title: String, due: Int? = nil, repeat rule: RepeatRule? = nil,
            assignee: Person? = nil, remindAt: Date? = nil, done: Bool = false, doneBy: Person? = nil
        ) -> TaskItem {
            let dueDay = due.map(cday)
            return TaskItem(
                space: space, title: title, dueDay: dueDay, repeatRule: rule, anchorDay: dueDay?.day ?? 0,
                assignee: space == .personal ? .alex : assignee,
                reminder: remindAt.map { TaskReminder(remindAt: $0, recipient: assignee ?? .alex) },
                createdBy: .alex, done: done, doneBy: doneBy, doneAt: done ? day(-1, 20) : nil
            )
        }

        let tasks: [TaskItem] = [
            task(.shared, "Pay the internet bill", due: 0, repeat: .monthly, assignee: .alex, remindAt: day(0, 19)),
            task(.shared, "Replace the water filter", due: 7, repeat: .everyTwoMonths),
            task(.shared, "Clean the bathroom", due: 1, repeat: .weekly, assignee: .sam),
            task(.shared, "Return the parcel", due: 2, assignee: .sam, remindAt: day(2, 9)),
            task(.shared, "Defrost the freezer"),
            task(.shared, "Take out the recycling", assignee: .sam, done: true, doneBy: .sam),
            task(.personal, "Book a dentist appointment", due: 9),
            task(.personal, "Renew gym membership", due: 8),
            task(.personal, "Call Mum", due: 1, repeat: .weekly),
        ]

        let notes: [Note] = [
            .init(space: .shared, title: "Weekend in Gdańsk",
                  body: "Train Fri 17:40 from Centralna.\nBook the flat near the old town.\nDinner Saturday — somewhere with pierogi.",
                  checklist: [.init(label: "Rain jackets", done: true), .init(label: "Chargers"), .init(label: "Train tickets")],
                  updatedAt: day(-1, 20), updatedBy: .sam),
            .init(space: .shared, title: "Wi‑Fi and building info",
                  body: "Network: Wola-Home\nIntercom code is at the front desk.\nBins go out Tuesday evening.",
                  updatedAt: day(-5, 12), updatedBy: .alex),
            .init(space: .shared, title: "Gift ideas for Mum’s birthday",
                  body: "Silk scarf, the cookbook she mentioned, a day at the spa together.",
                  updatedAt: day(-8, 12), updatedBy: .sam),
            .init(space: .personal, title: "Weekend plans",
                  body: "Saturday: market in the morning, then the new exhibition.\nSunday: long walk by the river, cook something slow.",
                  updatedAt: ago(hours: 2), updatedBy: .alex),
            .init(space: .personal, title: "Gift ideas for Sam",
                  body: "Ceramics class voucher. The green scarf from the market. Concert tickets for March?",
                  updatedAt: day(-3, 12), updatedBy: .alex),
            .init(space: .personal, title: "Books to read",
                  body: "A Philosophy of Software Design\nThe Overstory\nStolen Focus",
                  updatedAt: day(-10, 12), updatedBy: .alex),
        ]

        let trips: [Trip] = [
            .init(space: .shared, date: day(-3), shoppers: [.sam], itemCount: 6, total: pln("74.20"), receiptImageID: "h1"),
            .init(space: .shared, date: day(-6), shoppers: [.alex], itemCount: 9, total: pln("112.85"), receiptImageID: "h2"),
            .init(space: .shared, date: day(-7), shoppers: [.sam], itemCount: 14, total: pln("164.20"), receiptImageID: "h3"),
            .init(space: .shared, date: day(-14), shoppers: [.alex, .sam], itemCount: 18, total: pln("211.35"), receiptImageID: "h4"),
            .init(space: .shared, date: day(-17), shoppers: [.alex], itemCount: 4, total: nil),
            .init(space: .personal, date: day(-9), shoppers: [.alex], itemCount: 3, total: pln("46.97"), receiptImageID: "h6"),
        ]

        let receipt: [ReceiptLine] = [
            .init(name: "Oat milk", qty: "2 × 4,99", price: pln("9.98"), status: .matched),
            .init(name: "Tomatoes", qty: "1,02 kg", price: pln("9.18"), status: .matched),
            .init(name: "Sourdough bread", price: pln("12.50"), status: .matched),
            .init(name: "Greek yogurt", qty: "2 × 3,79", price: pln("7.58"), status: .matched),
            .init(name: "Spinach", price: pln("6.49"), status: .matched),
            .init(name: "Dark chocolate", price: pln("7.99"), status: .extra),
            .init(name: "Sparkling water", qty: "6 × 2,19", price: pln("13.14"), status: .extra),
            .init(name: "Bananas", qty: "1,1 kg", price: pln("6.05"), status: .extra),
        ]

        return MockData(
            lists: [shared, personal],
            groceries: groceries,
            suggestions: [.shared: [
                Suggestion(name: "Eggs", qty: "10", reason: "Bought 6 of the last 7 weeks"),
                Suggestion(name: "Bananas", reason: "Usually every week · last bought 8 days ago"),
                Suggestion(name: "Coffee beans", qty: "500 g", reason: "Every 3 weeks · last bought 20 days ago"),
            ]],
            tasks: tasks,
            notes: notes,
            trips: trips,
            receipt: receipt
        )
    }

    static let empty = MockData(lists: [], groceries: [], suggestions: [:], tasks: [], notes: [], trips: [], receipt: [])
}
