import Foundation
import Testing
@testable import Together

/// Deleting a trip from History: gone at once, sent to the server, and gone on the partner's phone via the event.
@MainActor
struct TripDeleteTests {
    final class Spy: StoreSync {
        var deleted: [Trip.ID] = []
        func record(_ change: StoreChange) {
            if case .tripDeleted(let trip) = change { deleted.append(trip.id) }
        }
        func loadLines(of tripID: Trip.ID) async {}
        func spacesChanged() async {}
    }

    @Test func deletingATripRemovesItAndSendsIt() throws {
        let store = AppStore(data: .make())
        let trip = try #require(store.trips(in: .shared).first)
        let spy = Spy()
        store.sync = spy
        let items = store.groceryItems

        #expect(store.deleteTrip(trip.id)?.id == trip.id)
        #expect(!store.trips.contains { $0.id == trip.id })
        #expect(spy.deleted == [trip.id])
        #expect(store.groceryItems == items, "the list stays as it is")
        #expect(store.deleteTrip(trip.id) == nil)
    }

    @Test func partnersDeleteArrivesAsAnEvent() throws {
        let store = AppStore(data: .make())
        let trip = try #require(store.trips(in: .shared).first)
        let sync = RemoteSync(client: APIClient(baseURL: URL(string: "https://api.test")!, vault: nil), store: store,
                              toasts: ToastCenter(), me: .alex, cachesLoads: false)
        defer { sync.stop() }
        let event = try APICoding.decoder.decode(SpaceEventDTO.self, from: Data("""
            {"type":"trip.deleted","space_id":"\(UUID())","actor_id":"\(Person.sam.id)","at":"2026-11-12T10:00:00Z",
             "removed_id":"\(trip.id)"}
            """.utf8))

        sync.apply(event, in: .shared)

        #expect(!store.trips.contains { $0.id == trip.id })
    }
}
