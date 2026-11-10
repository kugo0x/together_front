import Foundation
import Testing
@testable import Together

@MainActor
struct ReceiptStoreTests {
    /// Monday 9 Nov 2026, 15:37 in Warsaw.
    static let now = instant(2026, 11, 9, 15, 37)

    func makeStore() -> AppStore {
        let now = Self.now
        return AppStore(data: .make(now: now, calendar: warsaw), clock: { now }, calendar: warsaw)
    }

    /// The Shared list with a few Polish items, as someone shopping at Biedronka would have it.
    func storeWithPolishList() -> AppStore {
        let store = makeStore()
        for name in ["Mleko owsiane", "Pomidory", "Chleb", "Szpinak", "Banany"] {
            _ = store.addItem(name: name, in: .shared)
        }
        return store
    }

    /// What the backend would answer for `fixture`, as the review the sheet shows.
    func review(_ fixture: ReceiptFixture, _ store: AppStore, in space: SpaceKind = .shared) async throws -> ReceiptReview {
        let now = Self.now
        let recognizer = FakeReceiptRecognizer(fixture: fixture, delay: .zero, candidates: { store.receiptCandidates(in: $0) },
                                               now: { now }, calendar: warsaw)
        let scanned = try await recognizer.recognize([Data()], in: space)
        return ReceiptReview(scanned: scanned, candidates: store.receiptCandidates(in: space), now: now, calendar: warsaw)
    }

    // MARK: Review

    @Test func reviewShowsTheServersMatching() async throws {
        let r = try await review(.biedronka, storeWithPolishList())
        #expect(Set(r.matched.compactMap(\.match?.name)) == ["Mleko owsiane", "Pomidory", "Chleb", "Szpinak", "Banany"])
        #expect(Set(r.extra.map(\.name)) == ["Czekolada gorzka", "Woda gazowana 1,5 l"])
        #expect(r.unclear.map(\.name) == ["Jogurt grecki 400 g", "***"])
        #expect(r.unclear.first?.didYouMean?.name == "Greek yogurt")
        #expect(r.merchant == "Biedronka")
        #expect(r.date == Self.now, "printed today")
        #expect(r.total == Decimal(string: "71.91"))
        #expect(r.confirmTitle == "Mark 5 as bought")
    }

    @Test func totalFallsBackToTheLinesWhenUnread() {
        let scanned = ScannedReceipt(merchant: nil, total: nil, lines: [
            .init(raw: "A", name: "A", price: 2, status: .extra), .init(raw: "B", name: "B", price: Decimal(string: "3.5"), status: .extra),
        ])
        #expect(ReceiptReview(scanned: scanned, candidates: [], now: Self.now).total == Decimal(string: "5.5"))
        let unreadable = ScannedReceipt(merchant: nil, total: nil, lines: [.init(raw: "A", name: "A", status: .unclear)])
        #expect(ReceiptReview(scanned: unreadable, candidates: [], now: Self.now).total == nil)
    }

    @Test func reviewingChangesNothing() async throws {
        let store = storeWithPolishList()
        let items = store.groceryItems, trips = store.trips
        var r = try await review(.biedronka, store)
        r.toggle(r.lines[0].id)
        r.keepAsExtra(r.lines[1].id)
        r.rename(r.lines[2].id, to: "Chleb razowy")
        r.setPrice(r.lines[3].id, 1)
        r.acceptSuggestion(r.lines[3].id)
        r.total = 10
        #expect(store.groceryItems == items, "nothing is applied before Confirm")
        #expect(store.trips == trips)
    }

    @Test func confirmMarksMatchedBoughtViaReceiptAndSavesTheTrip() async throws {
        let store = storeWithPolishList()
        let openBefore = store.toBuy(in: .shared).count
        let r = try await review(.biedronka, store)
        let result = store.confirmReceipt(r, in: .shared)

        #expect(result.bought == 5)
        #expect(store.toBuy(in: .shared).count == openBefore - 5)
        for name in ["Mleko owsiane", "Pomidory", "Chleb", "Szpinak", "Banany"] {
            let item = try #require(store.bought(in: .shared).first { $0.name == name })
            #expect(item.viaReceipt)
            #expect(item.boughtBy == .alex)
            #expect(item.boughtAt == Self.now)
        }
        // Extras go to history only — never onto the list.
        #expect(!store.groceries(in: .shared).contains { $0.name.hasPrefix("Czekolada") })

        let trip = result.trip
        #expect(store.trips(in: .shared).first == trip)
        #expect(trip.total == Decimal(string: "71.91"))
        #expect(trip.merchant == "Biedronka")
        #expect(trip.itemCount == 9)
        #expect(trip.lines.count == 9)
        #expect(trip.hasReceipt)
        #expect(trip.metaText(me: .alex) == "Biedronka · You · 9 items")
    }

    @Test func excludedLinesAreLeftOut() async throws {
        let store = storeWithPolishList()
        var r = try await review(.biedronka, store)
        let milk = try #require(r.matched.first { $0.match?.name == "Mleko owsiane" })
        let water = try #require(r.extra.first { $0.name.hasPrefix("Woda") })
        r.toggle(milk.id)
        r.toggle(water.id)
        #expect(r.confirmTitle == "Mark 4 as bought")
        let result = store.confirmReceipt(r, in: .shared)
        #expect(result.bought == 4)
        #expect(store.toBuy(in: .shared).contains { $0.name == "Mleko owsiane" })
        #expect(result.trip.itemCount == 7)
        #expect(!result.trip.lines.contains { $0.name.hasPrefix("Woda") })
    }

    @Test func didYouMeanAndChoosingFromTheList() async throws {
        let store = makeStore() // English mock list
        var r = try await review(.corner, store)
        #expect(Set(r.matched.compactMap(\.match?.name)) == ["Oat milk", "Tomatoes", "Sourdough bread"])
        #expect(r.extra.map(\.name) == ["Dark chocolate"])
        let garbled = try #require(r.unclear.first)
        #expect(garbled.didYouMean?.name == "Greek yogurt")

        r.acceptSuggestion(garbled.id)
        #expect(r.confirmTitle == "Mark 4 as bought")

        // The chocolate was on the list as "Lemons"? Pick it by hand — taken items aren't offered.
        let chocolate = try #require(r.extra.first)
        let offered = r.freeCandidates(for: chocolate.id).map(\.name)
        #expect(!offered.contains("Oat milk") && !offered.contains("Greek yogurt"))
        #expect(offered.contains("Lemons"))
        r.assign(chocolate.id, to: try #require(r.candidates.first { $0.name == "Lemons" }))
        #expect(r.confirmTitle == "Mark 5 as bought")

        // Renaming changes what history shows, never what it matches.
        r.rename(chocolate.id, to: "Gorzka czekolada")
        #expect(r.lines.first { $0.id == chocolate.id }?.match?.name == "Lemons")
    }

    @Test func anItemCantBeTakenTwice() async throws {
        let store = makeStore()
        var r = try await review(.corner, store)
        let chocolate = try #require(r.extra.first)
        let oatMilk = try #require(r.candidates.first { $0.name == "Oat milk" })
        r.assign(chocolate.id, to: oatMilk)
        #expect(r.lines.first { $0.id == chocolate.id }?.status == .extra)
        #expect(r.matched.filter { $0.match?.name == "Oat milk" }.count == 1)
    }

    @Test func unreadableLinesGoToHistoryIfLeftAsIs() async throws {
        let store = storeWithPolishList()
        let r = try await review(.biedronka, store)
        let result = store.confirmReceipt(r, in: .shared)
        #expect(result.trip.lines.contains { $0.name == "***" && $0.status == .unclear && $0.price == nil })
    }

    @Test func aTickFromTodayIsFiledNotDoubleCounted() async throws {
        let store = storeWithPolishList()
        let bread = try #require(store.toBuy(in: .shared).first { $0.name == "Chleb" })
        _ = store.markBought(bread.id, in: .shared)
        let r = try await review(.biedronka, store)
        #expect(r.matched.contains { $0.match?.name == "Chleb" && $0.match?.alreadyBought == true })
        let result = store.confirmReceipt(r, in: .shared)
        #expect(result.bought == 4, "the bread was already ticked")
        #expect(store.bought(in: .shared).first { $0.id == bread.id }?.viaReceipt == true)
    }

    @Test func aSharedReceiptNeverTouchesPersonalItems() async throws {
        let store = makeStore()
        _ = store.addItem(name: "Chleb", in: .personal)
        let r = try await review(.biedronka, store, in: .shared)
        #expect(!r.matched.contains { $0.match?.name == "Chleb" })
        #expect(!r.candidates.contains { $0.name == "Chleb" })
        store.confirmReceipt(r, in: .shared)
        #expect(store.toBuy(in: .personal).contains { $0.name == "Chleb" })
        #expect(store.trips(in: .personal).count == 1, "the trip went to Shared")
    }

    // MARK: History

    @Test func monthTotals() {
        let store = makeStore()
        // Mock Shared trips: 6, 3 and 2 Nov with totals; 26 Oct with a total; 23 Oct without a receipt.
        let months = store.tripMonths(in: .shared)
        #expect(months.map(\.name) == ["November", "October"])
        #expect(months[0].total == Decimal(string: "351.25"))
        #expect(months[0].tripsWithTotal == 3)
        #expect(months[1].total == Decimal(string: "211.35"))
        #expect(months[1].trips.count == 2)
        #expect(months[1].tripsWithTotal == 1)
        #expect(Money.pln(months[0].total) == "351,25 zł")

        #expect(store.monthSummary(containing: Self.now, in: .shared) == months[0])
        #expect(store.monthSummary(containing: instant(2026, 9, 1, 12), in: .shared).trips.isEmpty)
    }

    @Test func aConfirmedReceiptCountsInItsMonth() async throws {
        let store = storeWithPolishList()
        store.confirmReceipt(try await review(.biedronka, store), in: .shared)
        #expect(store.monthSummary(containing: Self.now, in: .shared).total == Decimal(string: "423.16"))
    }

    @Test func moneyParsing() {
        #expect(Money.parse("78,4") == Decimal(string: "78.4"))
        #expect(Money.parse("1 234,50 zł") == Decimal(string: "1234.5"))
        #expect(Money.parse("") == nil)
        #expect(Money.parse("12,3,4") == nil)
        #expect(Money.number(Decimal(string: "71.9")!) == "71,90")
        #expect(Money.decimal(grosze: 7840) == Decimal(string: "78.4"))
    }
}
