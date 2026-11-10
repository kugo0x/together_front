import Foundation
import Observation

/// The scan session behind `ScanReceiptSheet` (CLAUDE.md → "Multiple receipt photos": explicit grouping, never
/// automatic):
/// - one receipt = 1–5 photos of the same receipt, sent together → one review → one trip;
/// - several receipts = a queue, read in parallel and reviewed one by one ("Receipt 2 of 3") → a trip each.
/// Nothing reaches the list or History before the person confirms a review.
@MainActor
@Observable
final class ReceiptScanFlow {
    nonisolated static let maxPages = 5

    struct Page: Identifiable, Equatable {
        let id = UUID()
        /// Prepared by `ReceiptImage` (≤ 1568 px, no metadata).
        let jpeg: Data
    }

    struct Receipt: Identifiable {
        enum State {
            case reading
            case ready(ReceiptReview)
            case failed(ReceiptScanError)
            case confirmed(Trip, bought: Int)
            case skipped
        }

        let id = UUID()
        let pages: [Data]
        var state: State
    }

    enum Step: Equatable {
        /// Camera or Photos.
        case capture
        /// The photos of one receipt, before sending: reorder, remove, add another.
        case pages
        /// Several photos picked: one receipt or separate receipts?
        case chooseGrouping
        /// Reading / reviewing the receipts, one at a time.
        case receipts
        /// Everything confirmed or skipped — "Scan another receipt".
        case finished
    }

    private(set) var step: Step = .capture
    private(set) var pages: [Page] = []
    /// Photos picked together, waiting for "parts of one receipt" vs "separate receipts".
    private(set) var pendingPhotos: [Data] = []
    private(set) var receipts: [Receipt] = []
    private(set) var current = 0

    @ObservationIgnored private let recognizer: ReceiptRecognizer
    @ObservationIgnored private let store: AppStore
    @ObservationIgnored private let space: SpaceKind
    @ObservationIgnored private var tasks: [Receipt.ID: Task<Void, Never>] = [:]

    init(recognizer: ReceiptRecognizer, store: AppStore, space: SpaceKind) {
        self.recognizer = recognizer
        self.store = store
        self.space = space
    }

    // MARK: Pages of one receipt

    var canAddPage: Bool { pages.count < Self.maxPages }

    /// Document-camera pages, or photos the person said are parts of this receipt. Extra ones past 5 are dropped.
    func addPages(_ jpegs: [Data]) {
        let room = Self.maxPages - pages.count
        pages += jpegs.prefix(max(0, room)).map(Page.init)
        if !pages.isEmpty { step = .pages }
    }

    func movePage(from source: Int, to destination: Int) {
        guard pages.indices.contains(source), pages.indices.contains(destination) else { return }
        pages.insert(pages.remove(at: source), at: destination)
    }

    func removePage(_ id: Page.ID) {
        pages.removeAll { $0.id == id }
        if pages.isEmpty { step = .capture }
    }

    /// Photos picked in Photos. One photo, or photos added to a receipt in progress, are its pages; several
    /// photos from the start need the person to say how they belong together.
    func photosPicked(_ jpegs: [Data]) {
        guard !jpegs.isEmpty else { return }
        if jpegs.count == 1 || step == .pages {
            addPages(jpegs)
        } else {
            pendingPhotos = jpegs
            step = .chooseGrouping
        }
    }

    /// "These are parts of one receipt" (the first 5).
    func groupAsOneReceipt() {
        let photos = pendingPhotos
        pendingPhotos = []
        addPages(photos)
    }

    /// "Separate receipts" — each photo is read on its own, all at once.
    func groupAsSeparateReceipts() {
        let photos = pendingPhotos
        pendingPhotos = []
        start(photos.map { [$0] })
    }

    /// "Read receipt" — sends this receipt's pages.
    func readPages() {
        guard !pages.isEmpty else { return }
        start([pages.map(\.jpeg)])
    }

    // MARK: Receipts

    var currentReceipt: Receipt? { receipts.indices.contains(current) ? receipts[current] : nil }

    /// "Receipt 2 of 3" when there's a queue.
    var progress: String? { receipts.count > 1 ? "Receipt \(current + 1) of \(receipts.count)" : nil }

    var isQueue: Bool { receipts.count > 1 }

    /// Edits on the review being looked at (nothing applied yet).
    func editReview(_ edit: (inout ReceiptReview) -> Void) {
        guard case .ready(var review)? = currentReceipt?.state else { return }
        edit(&review)
        receipts[current].state = .ready(review)
    }

    /// Confirm the review on screen: the list and History change now, for this receipt only.
    @discardableResult
    func confirmCurrent() -> (trip: Trip, bought: Int)? {
        guard case .ready(let review)? = currentReceipt?.state else { return nil }
        let result = store.confirmReceipt(review, in: space)
        receipts[current].state = .confirmed(result.trip, bought: result.bought)
        advance()
        return result
    }

    /// Discard this receipt (the others in the queue stay).
    func skipCurrent() {
        guard let receipt = currentReceipt else { return }
        tasks[receipt.id]?.cancel()
        receipts[current].state = .skipped
        advance()
    }

    /// Send the same photos again (offline, server trouble).
    func retryCurrent() {
        guard let receipt = currentReceipt, case .failed = receipt.state else { return }
        receipts[current].state = .reading
        read(at: current)
    }

    /// Cancel while reading: back to the photos (a queue is dropped — nothing was applied).
    func cancelReading() {
        cancelAll()
        receipts = []
        current = 0
        step = pages.isEmpty ? .capture : .pages
    }

    /// "Use another photo": start over with this receipt.
    func startOver() {
        cancelAll()
        receipts = []
        pages = []
        pendingPhotos = []
        current = 0
        step = .capture
    }

    /// "Scan another receipt" after confirming.
    func scanAnother() { startOver() }

    func cancelAll() {
        tasks.values.forEach { $0.cancel() }
        tasks = [:]
    }

    /// What was saved in this session, for the finished screen.
    var summary: String {
        let saved = receipts.compactMap { r -> (Trip, Int)? in
            if case .confirmed(let trip, let bought) = r.state { return (trip, bought) }
            return nil
        }
        let bought = saved.map(\.1).reduce(0, +)
        let boughtText = bought == 1 ? "1 item marked bought" : "\(bought) items marked bought"
        guard saved.count == 1 else {
            let receiptsText = saved.count == 1 ? "1 receipt saved" : "\(saved.count) receipts saved"
            return bought > 0 ? "\(receiptsText) · \(boughtText)" : receiptsText
        }
        let total = saved[0].0.total.map { " · " + Money.pln($0) } ?? ""
        return (bought > 0 ? boughtText : "Receipt saved") + total
    }

    // MARK: Private

    private func start(_ groups: [[Data]]) {
        cancelAll()
        receipts = groups.map { Receipt(pages: $0, state: .reading) }
        current = 0
        step = .receipts
        for i in receipts.indices { read(at: i) } // in parallel
    }

    private func read(at index: Int) {
        let receipt = receipts[index]
        let recognizer = recognizer, space = space
        tasks[receipt.id] = Task { [weak self] in
            let state: Receipt.State
            do {
                let scanned = try await recognizer.recognize(receipt.pages, in: space)
                guard !Task.isCancelled, let self else { return }
                state = scanned.lines.isEmpty
                    ? .failed(.unreadable)
                    : .ready(ReceiptReview(scanned: scanned, candidates: self.store.receiptCandidates(in: space),
                                           now: self.store.now, calendar: self.store.calendar))
            } catch let error as ReceiptScanError {
                state = .failed(error)
            } catch {
                state = .failed(.unavailable)
            }
            guard !Task.isCancelled, let self, let i = self.receipts.firstIndex(where: { $0.id == receipt.id }) else { return }
            self.receipts[i].state = state
            self.tasks[receipt.id] = nil
        }
    }

    private func advance() {
        guard let next = receipts.indices.first(where: { i in
            switch receipts[i].state {
            case .reading, .ready, .failed: true
            case .confirmed, .skipped: false
            }
        }) else {
            current = receipts.count
            step = .finished
            return
        }
        current = next
        // An earlier receipt may have ticked items: offer what's still on the list for "Choose from your list".
        if case .ready(var review) = receipts[next].state {
            review.candidates = store.receiptCandidates(in: space)
            receipts[next].state = .ready(review)
        }
    }
}
