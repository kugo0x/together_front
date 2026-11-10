import Foundation

/// Something a receipt line can correspond to: an open list item, or a tick from the last 24 h not yet in a trip
/// (back/api/openapi.yaml `ReceiptCandidate`).
struct ReceiptCandidate: Equatable, Hashable, Sendable {
    var itemID: GroceryItem.ID
    var name: String
    /// Already ticked — the receipt files that tick into the trip instead of ticking again (`purchase_id`).
    var alreadyBought = false
}

/// What `POST /v1/spaces/{id}/receipts/scan` answers: the backend reads the photo (Claude API, structured output)
/// and runs its matching, so every line already says matched / extra / unclear. Nothing is applied yet —
/// the app shows it for review and only `POST /receipts` changes anything.
struct ScannedReceipt: Equatable, Sendable {
    struct Line: Equatable, Sendable {
        var name: String
        /// "2 × 4,99", "1,020 kg × 9,00"
        var qty: String?
        /// `nil` when the price couldn't be read.
        var price: Decimal?
        var status: ReceiptLineStatus
        /// Matched: the list item it ticks.
        var match: ReceiptCandidate?
        /// Unclear: a plausible list item ("Did you mean Dish sponges?").
        var didYouMean: ReceiptCandidate?
    }

    var merchant: String?
    var shoppedAt: Date?
    /// "SUMA PLN"; `nil` when it couldn't be read.
    var total: Decimal?
    var lines: [Line]
}
