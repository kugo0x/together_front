import Foundation

/// The review step (design: ReceiptReview): the server's matched lines, editable, nothing applied until Confirm.
/// Built from `ScannedReceipt`; the edits become the body of `POST /v1/spaces/{id}/receipts`. Matching itself
/// happens on the server — here a line only changes when the person says so.
struct ReceiptReview: Equatable, Sendable {
    struct Line: Identifiable, Equatable, Sendable {
        var id = UUID()
        var name: String
        var qty: String?
        var price: Decimal?
        var status: ReceiptLineStatus
        /// Matched: the list item it ticks.
        var match: ReceiptCandidate?
        /// Unclear: a plausible list item ("Did you mean Dish sponges?").
        var didYouMean: ReceiptCandidate?
        /// Unticked lines (a colleague's coffee) are left out of everything.
        var included = true
    }

    var merchant: String?
    var date: Date
    var lines: [Line]
    /// The trip total — the receipt's "SUMA PLN", editable; the lines' sum when it couldn't be read.
    var total: Decimal?
    /// The list items a line can be pointed at by hand ("Choose from your list").
    var candidates: [ReceiptCandidate]

    init(scanned: ScannedReceipt, candidates: [ReceiptCandidate], now: Date) {
        lines = scanned.lines.map {
            Line(name: $0.name, qty: $0.qty, price: $0.price, status: $0.status, match: $0.match, didYouMean: $0.didYouMean)
        }
        merchant = scanned.merchant
        date = scanned.shoppedAt ?? now
        self.candidates = candidates
        total = scanned.total ?? (lines.contains { $0.price == nil } ? nil : lines.compactMap(\.price).reduce(0, +))
    }

    var matched: [Line] { lines.filter { $0.status == .matched } }
    var extra: [Line] { lines.filter { $0.status == .extra } }
    var unclear: [Line] { lines.filter { $0.status == .unclear } }

    /// "Mark 5 as bought" counts the included matched lines.
    var markCount: Int { matched.filter(\.included).count }
    var includedSum: Decimal { lines.filter(\.included).compactMap(\.price).reduce(0, +) }

    /// The primary button: "Mark 5 as bought", or "Save to history" when nothing is on the list.
    var confirmTitle: String { markCount > 0 ? "Mark \(markCount) as bought" : "Save to history" }

    /// List items no other line has taken — what "Choose from your list" offers.
    func freeCandidates(for id: Line.ID) -> [ReceiptCandidate] {
        guard let i = index(id) else { return [] }
        return candidates.filter { !isUsed($0, except: i) }
    }

    // MARK: Edits (none of them touch the list)

    mutating func toggle(_ id: Line.ID) {
        guard let i = index(id) else { return }
        lines[i].included.toggle()
    }

    /// "Did you mean …" accepted: the line is that item.
    mutating func acceptSuggestion(_ id: Line.ID) {
        guard let i = index(id), let candidate = lines[i].didYouMean else { return }
        assign(id, to: candidate)
    }

    /// The person picked the list item this line is.
    mutating func assign(_ id: Line.ID, to candidate: ReceiptCandidate) {
        guard let i = index(id), !isUsed(candidate, except: i) else { return }
        lines[i].status = .matched
        lines[i].match = candidate
        lines[i].didYouMean = nil
    }

    /// Not on the list: history only.
    mutating func keepAsExtra(_ id: Line.ID) {
        guard let i = index(id) else { return }
        lines[i].status = .extra
        lines[i].match = nil
        lines[i].didYouMean = nil
    }

    /// What the line really says (for history); doesn't change what it matches.
    mutating func rename(_ id: Line.ID, to name: String) {
        guard let i = index(id) else { return }
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { lines[i].name = trimmed }
    }

    mutating func setPrice(_ id: Line.ID, _ price: Decimal?) {
        guard let i = index(id) else { return }
        lines[i].price = price
    }

    private func index(_ id: Line.ID) -> Int? { lines.firstIndex { $0.id == id } }

    private func isUsed(_ candidate: ReceiptCandidate, except i: Int) -> Bool {
        lines.indices.contains { $0 != i && lines[$0].status == .matched && lines[$0].match?.itemID == candidate.itemID }
    }
}

/// One month of History: its trips and the month line.
struct TripMonth: Identifiable, Equatable, Sendable {
    struct Key: Hashable, Sendable {
        var year: Int
        var month: Int
    }

    var key: Key
    var trips: [Trip]

    var id: Key { key }
    /// Sum of the trips that have a total (receipts); trips without one are "—".
    var total: Decimal { trips.compactMap(\.total).reduce(0, +) }
    var tripsWithTotal: Int { trips.filter { $0.total != nil }.count }

    /// "November".
    var name: String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        return calendar.standaloneMonthSymbols[key.month - 1]
    }
}
