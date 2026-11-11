import Foundation
import Testing
@testable import Together

/// Grocery behaviour of `AppStore` (HANDOFF §6.3), shaped like the backend grocery API.
@MainActor
struct GroceryStoreTests {
    func makeStore() -> AppStore {
        let now = AppStoreTests.now
        return AppStore(data: .make(now: now), clock: { now })
    }

    // MARK: Quick add

    @Test("Quick add parses the quantity and puts the item on top of To buy", arguments: [
        ("2 oat milk", "Oat milk", "2"),
        ("1 kg apples", "Apples", "1 kg"),
        ("3x eggs", "Eggs", "3"),
        ("tomatoes", "Tomatoes", nil),
    ] as [(String, String, String?)])
    func quickAdd(text: String, name: String, qty: String?) throws {
        let store = makeStore()
        let item = try #require(store.addItem(text: text, in: .shared))
        #expect(item.name == name)
        #expect(item.qty == qty)
        #expect(item.addedBy == .alex)
        #expect(!item.done)
        #expect(store.toBuy(in: .shared).first?.id == item.id)
        #expect(store.space(of: item) == .shared)
    }

    @Test func quickAddIgnoresBlankInput() {
        let store = makeStore()
        let before = store.groceryItems.count
        #expect(store.addItem(text: "   ", in: .shared) == nil)
        #expect(store.addItem(name: " \n", in: .shared) == nil)
        #expect(store.groceryItems.count == before)
    }

    @Test func fieldsAreTrimmedAndCappedLikeTheAPI() throws {
        let store = makeStore()
        let item = try #require(store.addItem(name: "  " + String(repeating: "a", count: 100), qty: " ", note: " ok ", in: .personal))
        #expect(item.name.count == AppStore.Limits.name)
        #expect(item.qty == nil)
        #expect(item.note == "ok")
    }

    // MARK: Check / uncheck + Undo

    @Test func checkingMovesToBoughtWithAttributionAndUndoMovesBack() throws {
        let store = makeStore()
        let item = try #require(store.toBuy(in: .shared).first { $0.name == "Tomatoes" })

        _ = try #require(store.markBought(item.id, in: .shared))
        let bought = try #require(store.bought(in: .shared).first)
        #expect(bought.id == item.id, "most recent purchase first")
        #expect(bought.boughtBy == .alex)
        #expect(bought.boughtAt == AppStoreTests.now)
        #expect(!store.toBuy(in: .shared).contains { $0.id == item.id })

        // Idempotent, like POST …/bought.
        #expect(store.markBought(item.id, in: .shared)?.boughtAt == AppStoreTests.now)

        _ = try #require(store.unmarkBought(item.id, in: .shared))
        let back = try #require(store.toBuy(in: .shared).first { $0.id == item.id })
        #expect(back.boughtBy == nil && back.boughtAt == nil)
        #expect(store.toBuy(in: .shared).map(\.name).firstIndex(of: "Tomatoes") == 1, "keeps its place")
    }

    @Test func boughtShowsWhoAndWhen() throws {
        let store = makeStore()
        let row = GroceryItemRow(
            item: try #require(store.bought(in: .shared).first { $0.name == "Pasta" }),
            dates: RelativeDate(now: AppStoreTests.now),
            me: .alex,
            onToggle: {}
        )
        #expect(row.by == .sam)
        #expect(row.when == "yesterday")
    }

    @Test func partnerAddedItemsSayWho() throws {
        let store = makeStore()
        let dates = RelativeDate(now: AppStoreTests.now)
        let oat = try #require(store.toBuy(in: .shared).first { $0.name == "Oat milk" })
        #expect(GroceryItemRow(item: oat, dates: dates, me: .alex, onToggle: {}).note == "Sam added")
        let mine = try #require(store.addItem(name: "Rice", in: .shared))
        #expect(GroceryItemRow(item: mine, dates: dates, me: .alex, onToggle: {}).note == nil)
    }

    // MARK: Delete + Undo, edit

    @Test func deleteAndUndoPutsTheItemBackInPlace() throws {
        let store = makeStore()
        let order = store.toBuy(in: .shared).map(\.id)
        let removed = try #require(store.removeItem(order[2], in: .shared))
        #expect(!store.toBuy(in: .shared).contains { $0.id == order[2] })

        store.undoRemove(removed)
        #expect(store.toBuy(in: .shared).map(\.id) == order)

        store.undoRemove(removed)
        #expect(store.toBuy(in: .shared).count == order.count, "Undo twice doesn't duplicate")
    }

    @Test func editChangesFieldsAndEmptyClears() throws {
        let store = makeStore()
        let spinach = try #require(store.toBuy(in: .shared).first { $0.name == "Spinach" })
        let edited = try #require(store.updateItem(spinach.id, in: .shared, name: " Baby spinach ", qty: "200 g", note: ""))
        #expect(edited.name == "Baby spinach")
        #expect(edited.qty == "200 g")
        #expect(edited.note == nil)
        #expect(store.updateItem(spinach.id, in: .shared, name: "  ", qty: nil, note: nil) == nil, "name is required")
    }

    // MARK: Suggestions

    @Test func addOneSuggestion() throws {
        let store = makeStore()
        let added = store.acceptSuggestions(named: ["Coffee beans"], in: .shared)
        #expect(added.map(\.name) == ["Coffee beans"])
        #expect(added.first?.qty == "500 g")
        #expect(store.toBuy(in: .shared).first?.name == "Coffee beans")
        #expect(!store.suggestions(in: .shared).contains { $0.name == "Coffee beans" })
    }

    @Test func skipHidesWithoutAdding() {
        let store = makeStore()
        let before = store.groceryItems.count
        store.dismissSuggestion(named: "Eggs", in: .shared)
        #expect(store.suggestions(in: .shared).map(\.name) == ["Bananas", "Coffee beans"])
        #expect(store.groceryItems.count == before)
    }

    @Test func addAllKeepsCardOrderAndEmptiesTheCard() {
        let store = makeStore()
        let names = store.suggestions(in: .shared).map(\.name)
        let added = store.acceptSuggestions(named: names, in: .shared)
        #expect(added.map(\.name) == ["Eggs", "Bananas", "Coffee beans"])
        #expect(Array(store.toBuy(in: .shared).prefix(3)).map(\.name) == names)
        #expect(store.suggestions(in: .shared).isEmpty)
    }

    @Test func suggestionAlreadyOnTheListIsNotDuplicated() throws {
        let store = makeStore()
        _ = try #require(store.addItem(text: "eggs", in: .shared))
        let added = store.acceptSuggestions(named: ["Eggs"], in: .shared)
        #expect(added.isEmpty)
        #expect(store.toBuy(in: .shared).filter { $0.name == "Eggs" }.count == 1)
        #expect(!store.suggestions(in: .shared).contains { $0.name == "Eggs" })
    }

    @Test func suggestionsOffHidesTheCardAndNothingIsAutoAdded() {
        let store = makeStore()
        let before = store.groceryItems.count
        store.suggestionsEnabled = false
        #expect(store.suggestions(in: .shared).isEmpty)
        #expect(store.acceptSuggestions(named: ["Eggs"], in: .shared).isEmpty)
        #expect(store.groceryItems.count == before)
        store.suggestionsEnabled = true
        #expect(store.suggestions(in: .shared).count == 3)
    }

    // MARK: Space isolation

    @Test func personalItemsNeverReachShared() throws {
        let store = makeStore()
        let secret = try #require(store.addItem(text: "2 birthday candles", in: .personal))
        #expect(!store.groceries(in: .shared).contains { $0.id == secret.id })
        #expect(store.groceries(in: .personal).contains { $0.id == secret.id })
        #expect(store.groceries(in: .shared).allSatisfy { store.space(of: $0) == .shared })
        #expect(store.suggestions(in: .personal).isEmpty)
        #expect(store.recentTrips(in: .shared).allSatisfy { $0.space == .shared })
    }

    @Test func itemOperationsAreScopedToTheirSpace() throws {
        let store = makeStore()
        let personal = try #require(store.toBuy(in: .personal).first)
        // Like the API's 404: an item of another space can't be touched from Shared.
        #expect(store.item(personal.id, in: .shared) == nil)
        #expect(store.markBought(personal.id, in: .shared) == nil)
        #expect(store.updateItem(personal.id, in: .shared, name: "x", qty: nil, note: nil) == nil)
        #expect(store.removeItem(personal.id, in: .shared) == nil)
        #expect(store.toBuy(in: .personal).first == personal)
    }

    // MARK: Trips and money

    @Test func recentTripsAreTheLatestTwo() {
        let store = makeStore()
        let trips = store.recentTrips(in: .shared)
        #expect(trips.count == 2)
        #expect(trips.map(\.amountText) == ["74,20 zł", "112,85 zł"])
        #expect(trips.map { $0.metaText(me: .alex) } == ["Sam · 6 items", "You · 9 items"])
    }

    @Test func tripText() {
        let store = makeStore()
        let all = store.trips(in: .shared)
        #expect(all[3].metaText(me: .alex) == "You & Sam · 18 items")
        #expect(all[4].metaText(me: .alex) == "You · 4 items · no receipt")
        #expect(all[4].amountText == "—")
        #expect(all[0].dateText() == "Wed, 4 Nov")
    }

    @Test func plnUsesACommaDecimal() {
        #expect(Money.pln(Decimal(string: "78.4")!) == "78,40 zł")
        #expect(Money.pln(Money.decimal(grosze: 7840)) == "78,40 zł")
        #expect(Money.pln(0) == "0,00 zł")
    }
}
