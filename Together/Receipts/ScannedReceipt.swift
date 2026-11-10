import Foundation

/// Something a receipt line can correspond to: an open list item, or a tick from the last 24 h not yet in a trip
/// (back/api/openapi.yaml `ReceiptCandidate`).
struct ReceiptCandidate: Equatable, Hashable, Sendable {
    var itemID: GroceryItem.ID
    var name: String
    /// Already ticked — the receipt files that tick into the trip instead of ticking again (`purchase_id`).
    var alreadyBought = false
}

/// What `POST /v1/spaces/{id}/receipts/scan` answers (back/api/openapi.yaml 0.8.0 `ReceiptScan`): the backend reads
/// the photos (Claude API, structured output) and runs its matching, so every line already says matched / extra /
/// unclear. Nothing is applied yet — the app shows it for review and only `POST /receipts` changes anything.
struct ScannedReceipt: Equatable, Sendable {
    enum Confidence: String, Codable, Sendable {
        case high, medium, low
    }

    struct Line: Equatable, Sendable {
        /// As printed: "MLK OWS 1L".
        var raw: String
        /// Clean name with abbreviations spelled out: "Mleko owsiane 1 l".
        var name: String
        /// The server's short quantity: "2", "0.456 kg"; `nil` for a single piece.
        var qty: String?
        /// 2, or 0.456 for weighed goods.
        var quantity: Decimal?
        /// szt, kg, g, l, ml, opak.
        var unit: String?
        /// Per piece or per kg.
        var unitPrice: Decimal?
        /// Printed line value before discounts.
        var linePrice: Decimal?
        /// "Rabat" / "opust" applied to this line.
        var discount: Decimal = 0
        /// What was paid (line − discount); `nil` when it couldn't be read. This goes to Confirm.
        var price: Decimal?
        var status: ReceiptLineStatus
        var confidence: Confidence = .high
        /// The recognizer isn't sure — the person must check this line (never `matched`).
        var unclear = false
        /// Matched: the list item it ticks.
        var match: ReceiptCandidate?
        /// Unclear: a plausible list item ("Did you mean Dish sponges?").
        var didYouMean: ReceiptCandidate?

        /// "2 × 4,99", "0,456 kg × 21,90" — from the quantity and unit price when both were read.
        var quantityText: String? {
            if let quantity, let unitPrice {
                let isPiece = unit == nil || unit == "szt" || unit == "opak"
                let amount = isPiece ? Money.number(quantity, fractionDigits: 0) : Money.number(quantity, fractionDigits: 3) + " " + (unit ?? "")
                return isPiece && quantity == 1 ? nil : "\(amount) × \(Money.number(unitPrice))"
            }
            return qty
        }
    }

    var merchant: String?
    /// The sale date printed on the receipt (`purchased_on`, date only).
    var purchasedOn: DateComponents?
    var currency = "PLN"
    /// "SUMA PLN"; `nil` when it couldn't be read.
    var total: Decimal?
    /// Sum of the lines' prices.
    var linesTotal: Decimal = 0
    /// `false`: the lines don't add up to the printed total (ask the person to check the prices); `nil`: no total.
    var totalMatches: Bool?
    var lines: [Line]
}
