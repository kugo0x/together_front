import Foundation

/// A receipt as the backend would read it, for the stand-in recognizer, tests and `-receiptFixture <name>`.
struct ReceiptFixture: Sendable {
    struct Line: Sendable {
        var name: String
        var qty: String?
        var price: Decimal?
        /// The list item the server would match this line to (by name, if it's on the list).
        var matches: String?
        /// Unclear: the item it would suggest.
        var didYouMean: String?
        /// Unclear with nothing to suggest.
        var unreadable = false
    }

    var merchant: String?
    var minutesAgo: Double = 20
    var total: Decimal?
    var lines: [Line] = []
    var error: ReceiptScanError?

    static let all: [String: ReceiptFixture] = [
        "corner": corner, "biedronka": biedronka, "offline": offline, "unreadable": unreadable,
    ]

    private static func pln(_ s: String) -> Decimal { Decimal(string: s, locale: Locale(identifier: "en_US_POSIX"))! }

    /// The prototype's receipt against the app's mock Shared list: three items on the list, one extra,
    /// one garbled line that suggests "Greek yogurt".
    static let corner = ReceiptFixture(
        merchant: "Corner Market",
        total: pln("43.44"),
        lines: [
            .init(name: "Oat milk", qty: "2 × 4,99", price: pln("9.98"), matches: "Oat milk"),
            .init(name: "Tomatoes", qty: "1,020 kg × 9,00", price: pln("9.18"), matches: "Tomatoes"),
            .init(name: "Sourdough bread", price: pln("12.50"), matches: "Sourdough bread"),
            .init(name: "Dark chocolate", price: pln("7.99")),
            .init(name: "GRK YGHRT", price: pln("3.79"), didYouMean: "Greek yogurt"),
        ]
    )

    /// A Polish receipt (names as printed, rabat already applied by the server) against a Polish list.
    static let biedronka = ReceiptFixture(
        merchant: "Biedronka",
        total: pln("71.91"),
        lines: [
            .init(name: "MLEKO OWSIANE 1L", qty: "2 × 4,99", price: pln("9.98"), matches: "Mleko owsiane"),
            .init(name: "POMIDORY LUZ", qty: "1,020 kg × 9,00", price: pln("9.18"), matches: "Pomidory"),
            .init(name: "CHLEB NA ZAKWASIE", price: pln("12.50"), matches: "Chleb"),
            .init(name: "JOGURT GRECKI 400G", qty: "2 × 3,79", price: pln("6.58"), didYouMean: "Greek yogurt"),
            .init(name: "SZPINAK 150G", price: pln("6.49"), matches: "Szpinak"),
            .init(name: "CZEKOLADA GORZKA", price: pln("7.99")),
            .init(name: "WODA GAZOWANA 1,5L", qty: "6 × 2,19", price: pln("13.14")),
            .init(name: "BANANY LUZ", qty: "1,100 kg × 5,50", price: pln("6.05"), matches: "Banany"),
            .init(name: "***", unreadable: true),
        ]
    )

    static let offline = ReceiptFixture(error: .offline)
    static let unreadable = ReceiptFixture(error: .unreadable)
}
