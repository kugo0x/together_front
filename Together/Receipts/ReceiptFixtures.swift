import Foundation

/// A receipt as the backend would read it, for the stand-in recognizer, tests and `-receiptFixture <name>`. Lines
/// carry the real response's fields (raw text, clean name, quantity, unit and line price, rabat, confidence);
/// `matches` / `didYouMean` name the list item the server would pick.
struct ReceiptFixture: Sendable {
    struct Line: Sendable {
        var raw: String
        var name: String
        var quantity: Decimal?
        var unit: String?
        var unitPrice: Decimal?
        var linePrice: Decimal?
        var discount: Decimal = 0
        var confidence: ScannedReceipt.Confidence = .high
        /// The recognizer isn't sure about it (`unclear: true`).
        var unsure = false
        /// The list item the server would match this line to (by name, if it's on the list).
        var matches: String?
        /// Unsure lines: the item it would offer as "Did you mean".
        var didYouMean: String?

        /// `line − discount`, as the server sends `price_grosze`.
        var price: Decimal? { linePrice.map { $0 - discount } }
    }

    var merchant: String?
    /// Printed on the receipt; `nil` = today.
    var purchasedOn: DateComponents?
    /// "SUMA PLN".
    var total: Decimal?
    var lines: [Line] = []
    var error: ReceiptScanError?

    var linesTotal: Decimal { lines.compactMap(\.price).reduce(0, +) }

    static let all: [String: ReceiptFixture] = [
        "corner": corner, "biedronka": biedronka, "mismatch": mismatch,
        "offline": offline, "unreadable": unreadable, "notReceipt": notReceipt, "tooLong": tooLong,
        "busy": busy, "limit": limit, "disabled": disabled,
    ]

    private static func pln(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    /// The prototype's receipt against the app's mock Shared list: three items on the list, one extra,
    /// one line the recognizer wasn't sure about that suggests "Greek yogurt".
    static let corner = ReceiptFixture(
        merchant: "Corner Market",
        total: pln("43.44"),
        lines: [
            .init(raw: "OAT MILK 1L", name: "Oat milk", quantity: 2, unit: "szt", unitPrice: pln("4.99"), linePrice: pln("9.98"),
                  matches: "Oat milk"),
            .init(raw: "TOMATOES LOOSE", name: "Tomatoes", quantity: pln("1.02"), unit: "kg", unitPrice: pln("9.00"),
                  linePrice: pln("9.18"), matches: "Tomatoes"),
            .init(raw: "SOURDOUGH BREAD", name: "Sourdough bread", linePrice: pln("12.50"), matches: "Sourdough bread"),
            .init(raw: "DARK CHOC 70%", name: "Dark chocolate", linePrice: pln("7.99")),
            .init(raw: "GRK YGHRT", name: "GRK YGHRT", linePrice: pln("3.79"), confidence: .low, unsure: true,
                  didYouMean: "Greek yogurt"),
        ]
    )

    /// A Polish receipt (rabat on the yogurt, two weighed lines, an unreadable line) against a Polish list.
    static let biedronka = ReceiptFixture(
        merchant: "Biedronka",
        total: pln("71.91"),
        lines: [
            .init(raw: "MLEKO OWS 1L", name: "Mleko owsiane 1 l", quantity: 2, unit: "szt", unitPrice: pln("4.99"),
                  linePrice: pln("9.98"), matches: "Mleko owsiane"),
            .init(raw: "POMIDORY LUZ", name: "Pomidory luz", quantity: pln("1.02"), unit: "kg", unitPrice: pln("9.00"),
                  linePrice: pln("9.18"), matches: "Pomidory"),
            .init(raw: "CHLEB NA ZAKW.", name: "Chleb na zakwasie", linePrice: pln("12.50"), matches: "Chleb"),
            .init(raw: "JOG.GRECKI 400G", name: "Jogurt grecki 400 g", quantity: 2, unit: "szt", unitPrice: pln("3.79"),
                  linePrice: pln("7.58"), discount: pln("1.00"), confidence: .medium, unsure: true, didYouMean: "Greek yogurt"),
            .init(raw: "SZPINAK 150G", name: "Szpinak 150 g", linePrice: pln("6.49"), matches: "Szpinak"),
            .init(raw: "CZEKOL.GORZKA", name: "Czekolada gorzka", linePrice: pln("7.99")),
            .init(raw: "WODA GAZ.1,5L", name: "Woda gazowana 1,5 l", quantity: 6, unit: "szt", unitPrice: pln("2.19"),
                  linePrice: pln("13.14")),
            .init(raw: "BANANY LUZ", name: "Banany luz", quantity: pln("1.1"), unit: "kg", unitPrice: pln("5.50"),
                  linePrice: pln("6.05"), matches: "Banany"),
            .init(raw: "***", name: "***", confidence: .low, unsure: true),
        ]
    )

    /// The lines don't add up to "SUMA PLN" (one price misread): the review asks to check the prices.
    static let mismatch = ReceiptFixture(
        merchant: "Corner Market",
        total: pln("47.44"),
        lines: corner.lines
    )

    static let offline = ReceiptFixture(error: .offline)
    static let unreadable = ReceiptFixture(error: .unreadable)
    static let notReceipt = ReceiptFixture(error: .notAReceipt)
    static let tooLong = ReceiptFixture(error: .tooLong)
    static let busy = ReceiptFixture(error: .busy(retryAfter: 29))
    static let limit = ReceiptFixture(error: .dailyLimit(retryAfter: 6 * 3600))
    static let disabled = ReceiptFixture(error: .disabled)
}
