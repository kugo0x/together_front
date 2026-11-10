import Foundation

/// The review step (design: ReceiptReview): the server's matched lines, editable, nothing applied until Confirm.
/// Built from `ScannedReceipt`; the edits become the body of `POST /v1/spaces/{id}/receipts`. Matching itself
/// happens on the server — here a line only changes when the person says so.
struct ReceiptReview: Equatable, Sendable {
    struct Line: Identifiable, Equatable, Sendable {
        var id = UUID()
        var name: String
        /// As printed, when it differs from the clean name ("MLEKO OWS 1L").
        var raw: String?
        /// "2 × 4,99", "1,020 kg × 9,00".
        var qty: String?
        /// Rabat already taken off `price`.
        var discount: Decimal = 0
        var price: Decimal?
        var status: ReceiptLineStatus
        /// Matched: the list item it ticks.
        var match: ReceiptCandidate?
        /// Unclear: a plausible list item ("Did you mean Dish sponges?").
        var didYouMean: ReceiptCandidate?
        /// Unticked lines (a colleague's coffee) are left out of everything.
        var included = true

        /// Under the name: "MLEKO OWS 1L · 2 × 3,79 · rabat −1,00".
        var detail: String? {
            let parts = [raw, qty, discount > 0 ? "rabat −" + Money.number(discount) : nil].compactMap { $0 }
            return parts.isEmpty ? nil : parts.joined(separator: " · ")
        }
    }

    var merchant: String?
    var date: Date
    var lines: [Line]
    /// The trip total — the receipt's "SUMA PLN", editable; the lines' sum when it couldn't be read.
    var total: Decimal?
    /// The list items a line can be pointed at by hand ("Choose from your list").
    var candidates: [ReceiptCandidate]
    /// "SUMA PLN" as printed, and whether the server found the lines add up to it.
    let printedTotal: Decimal?
    let serverSaysTotalMatches: Bool?

    /// - Parameter now: the receipt's date when it wasn't printed or is today; another printed day keeps its date.
    init(scanned: ScannedReceipt, candidates: [ReceiptCandidate], now: Date, calendar: Calendar = .current) {
        lines = scanned.lines.map {
            Line(name: $0.name, raw: $0.raw.caseInsensitiveCompare($0.name) == .orderedSame ? nil : $0.raw,
                 qty: $0.quantityText, discount: $0.discount, price: $0.price, status: $0.status,
                 match: $0.match, didYouMean: $0.didYouMean)
        }
        merchant = scanned.merchant
        date = Self.date(scanned.purchasedOn, now: now, calendar: calendar)
        self.candidates = candidates
        printedTotal = scanned.total
        serverSaysTotalMatches = scanned.totalMatches
        total = scanned.total ?? (lines.contains { $0.price == nil } ? nil : lines.compactMap(\.price).reduce(0, +))
    }

    /// The lines don't add up to "SUMA PLN" (server: `total_matches: false`) and no price has been fixed to make
    /// them — "check the prices".
    var linesDontAddUp: Bool {
        guard serverSaysTotalMatches == false, let printedTotal else { return false }
        return lines.compactMap(\.price).reduce(0, +) != printedTotal
    }

    /// A printed day other than today becomes that day at noon (the receipt has no time we trust).
    private static func date(_ day: DateComponents?, now: Date, calendar: Calendar) -> Date {
        guard let day, let start = calendar.date(from: DateComponents(year: day.year, month: day.month, day: day.day)),
              !calendar.isDate(start, inSameDayAs: now), start < now else { return now }
        return calendar.date(byAdding: .hour, value: 12, to: start) ?? start
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
