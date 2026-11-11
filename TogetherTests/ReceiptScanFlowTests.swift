import Foundation
import os
import Testing
@testable import Together

/// The scan session: pages of one receipt vs a queue of different receipts (CLAUDE.md → "Multiple receipt photos").
@MainActor
struct ReceiptScanFlowTests {
    static let now = ReceiptStoreTests.now

    /// Records what each call was sent; answers with the fixtures in turn.
    final class Recorder: ReceiptRecognizer, @unchecked Sendable {
        let fake: FakeReceiptRecognizer
        let sent = OSAllocatedUnfairLock<[[Data]]>(initialState: [])

        init(_ fixtures: [ReceiptFixture], delay: Duration = .zero, store: AppStore) {
            let now = instant(2026, 11, 9, 15, 37)
            fake = FakeReceiptRecognizer(fixtures: fixtures, delay: delay, candidates: { store.receiptCandidates(in: $0) },
                                         now: { now })
        }

        func recognize(_ pages: [Data], in space: SpaceKind) async throws -> ScannedReceipt {
            sent.withLock { $0.append(pages) }
            return try await fake.recognize(pages, in: space)
        }

        var calls: [[Data]] { sent.withLock { $0 } }
    }

    func makeStore() -> AppStore {
        let now = Self.now
        return AppStore(data: .make(now: now, calendar: warsaw), clock: { now }, calendar: warsaw)
    }

    func photo(_ n: UInt8) -> Data { Data([0xFF, 0xD8, n, 0xFF, 0xD9]) }

    /// Waits for the background reads to land.
    func settle(_ flow: ReceiptScanFlow, _ done: (ReceiptScanFlow) -> Bool = { flow in
        !flow.receipts.contains { if case .reading = $0.state { true } else { false } }
    }) async {
        for _ in 0..<500 where !done(flow) { try? await Task.sleep(for: .milliseconds(5)) }
    }

    func isReady(_ r: ReceiptScanFlow.Receipt?) -> Bool { if case .ready? = r?.state { true } else { false } }

    // MARK: Pages of one receipt

    @Test func pagesAreCappedAtFive() {
        let store = makeStore()
        let flow = ReceiptScanFlow(recognizer: Recorder([.corner], store: store), store: store, space: .shared)
        flow.addPages((1...3).map { photo($0) })
        #expect(flow.step == .pages)
        #expect(flow.canAddPage)
        flow.addPages((4...7).map { photo($0) })
        #expect(flow.pages.map(\.jpeg) == (1...5).map { photo($0) }, "the extra photos are dropped")
        #expect(!flow.canAddPage)
    }

    @Test func pagesCanBeReorderedAndRemoved() {
        let store = makeStore()
        let flow = ReceiptScanFlow(recognizer: Recorder([.corner], store: store), store: store, space: .shared)
        flow.addPages([photo(1), photo(2), photo(3)])
        flow.movePage(from: 2, to: 1)
        #expect(flow.pages.map(\.jpeg) == [photo(1), photo(3), photo(2)])
        flow.movePage(from: 0, to: -1) // out of range: ignored
        #expect(flow.pages.map(\.jpeg) == [photo(1), photo(3), photo(2)])
        flow.removePage(flow.pages[0].id)
        flow.removePage(flow.pages[0].id)
        #expect(flow.pages.map(\.jpeg) == [photo(2)])
        flow.removePage(flow.pages[0].id)
        #expect(flow.step == .capture, "no photos left — back to the camera")
    }

    @Test func pagesOfOneReceiptAreSentTogetherAsOneReview() async {
        let store = makeStore()
        let recorder = Recorder([.corner], store: store)
        let flow = ReceiptScanFlow(recognizer: recorder, store: store, space: .shared)
        flow.addPages([photo(1)])
        flow.photosPicked([photo(2), photo(3)]) // "Add another photo of this receipt" — no grouping question
        #expect(flow.step == .pages)
        flow.movePage(from: 2, to: 0)
        flow.readPages()
        #expect(flow.step == .receipts)
        await settle(flow)
        #expect(recorder.calls == [[photo(3), photo(1), photo(2)]], "one call with the pages in the chosen order")
        #expect(flow.receipts.count == 1)
        #expect(flow.progress == nil && !flow.isQueue)
        #expect(isReady(flow.currentReceipt))

        let tripsBefore = store.trips(in: .shared).count
        flow.confirmCurrent()
        #expect(store.trips(in: .shared).count == tripsBefore + 1, "one receipt, one trip")
        #expect(flow.step == .finished)
        #expect(flow.summary == "3 items marked bought · 43,44 zł")
    }

    // MARK: Grouping

    @Test func severalPhotosAskHowTheyGoTogether() {
        let store = makeStore()
        let flow = ReceiptScanFlow(recognizer: Recorder([.corner], store: store), store: store, space: .shared)
        flow.photosPicked([photo(1)])
        #expect(flow.step == .pages, "one photo needs no question")
        flow.startOver()
        flow.photosPicked([photo(1), photo(2)])
        #expect(flow.step == .chooseGrouping)
        #expect(flow.pendingPhotos.count == 2)
        flow.groupAsOneReceipt()
        #expect(flow.step == .pages)
        #expect(flow.pages.map(\.jpeg) == [photo(1), photo(2)])
        #expect(flow.pendingPhotos.isEmpty)
    }

    @Test func partsOfOneReceiptKeepTheFirstFive() {
        let store = makeStore()
        let flow = ReceiptScanFlow(recognizer: Recorder([.corner], store: store), store: store, space: .shared)
        flow.photosPicked((1...7).map { photo($0) })
        flow.groupAsOneReceipt()
        #expect(flow.pages.map(\.jpeg) == (1...5).map { photo($0) })
    }

    // MARK: Queue

    @Test func separateReceiptsAreReadInParallelAndReviewedOneByOne() async {
        let store = makeStore()
        let recorder = Recorder([.corner, .biedronka, .corner], delay: .milliseconds(300), store: store)
        let flow = ReceiptScanFlow(recognizer: recorder, store: store, space: .shared)
        flow.photosPicked([photo(1), photo(2), photo(3)])
        let started = ContinuousClock.now
        flow.groupAsSeparateReceipts()
        #expect(flow.step == .receipts)
        await settle(flow)
        #expect(ContinuousClock.now - started < .milliseconds(800), "three 300 ms reads at once, not one after another")
        #expect(Set(recorder.calls) == [[photo(1)], [photo(2)], [photo(3)]], "each photo is its own receipt")
        #expect(flow.isQueue)
        #expect(flow.progress == "Receipt 1 of 3")

        let tripsBefore = store.trips(in: .shared).count
        flow.confirmCurrent()
        #expect(flow.progress == "Receipt 2 of 3")
        flow.skipCurrent()
        #expect(flow.progress == "Receipt 3 of 3")
        flow.confirmCurrent()
        #expect(flow.step == .finished)
        #expect(store.trips(in: .shared).count == tripsBefore + 2, "a trip per confirmed receipt, none for the skipped one")
        #expect(flow.summary == "2 receipts saved · 3 items marked bought",
                "the second Corner Market receipt finds its items already bought")
    }

    @Test func theNextReviewOnlyOffersItemsStillToBuy() async {
        let store = makeStore()
        let flow = ReceiptScanFlow(recognizer: Recorder([.corner, .corner], store: store), store: store, space: .shared)
        flow.photosPicked([photo(1), photo(2)])
        flow.groupAsSeparateReceipts()
        await settle(flow)
        flow.confirmCurrent()
        guard case .ready(let next)? = flow.currentReceipt?.state else { Issue.record("no second review"); return }
        #expect(next.candidates.contains { $0.name == "Lemons" })
        #expect(!next.candidates.contains { $0.name == "Tomatoes" && !$0.alreadyBought },
                "tomatoes were just bought via the first receipt")
    }

    @Test func aFailedReceiptInTheQueueCanBeRetriedOrSkipped() async throws {
        let store = makeStore()
        let flow = ReceiptScanFlow(recognizer: Recorder([.offline, .corner], store: store), store: store, space: .shared)
        flow.photosPicked([photo(1), photo(2)])
        flow.groupAsSeparateReceipts()
        await settle(flow)
        // Calls run in parallel, so either photo may have got the offline answer.
        let failed = flow.receipts.firstIndex { if case .failed(.offline) = $0.state { true } else { false } }
        #expect(failed != nil)
        let index = try #require(failed)
        if index == 0 {
            flow.retryCurrent()
            if case .reading? = flow.currentReceipt?.state {} else { Issue.record("retry sends the same photo again") }
            await settle(flow) // the stand-in cycles, so the retry is offline again
            #expect(flow.progress == "Receipt 1 of 2")
            flow.skipCurrent()
            flow.confirmCurrent()
        } else {
            flow.confirmCurrent()
            flow.skipCurrent()
        }
        #expect(flow.step == .finished)
        #expect(flow.summary.hasPrefix("3 items marked bought"))
    }

    // MARK: Cancel / start over

    @Test func cancellingWhileReadingAppliesNothing() async {
        let store = makeStore()
        let trips = store.trips, items = store.groceryItems
        let flow = ReceiptScanFlow(recognizer: Recorder([.corner], delay: .milliseconds(200), store: store),
                                   store: store, space: .shared)
        flow.addPages([photo(1), photo(2)])
        flow.readPages()
        flow.cancelReading()
        #expect(flow.step == .pages, "back to the photos")
        #expect(flow.pages.count == 2)
        try? await Task.sleep(for: .milliseconds(400))
        #expect(flow.receipts.isEmpty, "the cancelled read never lands")
        #expect(store.trips == trips && store.groceryItems == items)
    }

    @Test func scanAnotherStartsFresh() async {
        let store = makeStore()
        let flow = ReceiptScanFlow(recognizer: Recorder([.corner], store: store), store: store, space: .shared)
        flow.addPages([photo(1)])
        flow.readPages()
        await settle(flow)
        flow.confirmCurrent()
        flow.scanAnother()
        #expect(flow.step == .capture)
        #expect(flow.pages.isEmpty && flow.receipts.isEmpty && flow.pendingPhotos.isEmpty)
    }
}
