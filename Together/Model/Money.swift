import Foundation

/// PLN with a comma decimal: "78,40 zł" (HANDOFF §2.7). Money appears only as trip totals and the month line.
enum Money {
    private static let style = Decimal.FormatStyle
        .number
        .precision(.fractionLength(2))
        .locale(Locale(identifier: "pl_PL"))

    static func pln(_ amount: Decimal) -> String {
        amount.formatted(style) + " zł"
    }

    /// The API sends money as grosze (7840 = 78,40 zł).
    static func decimal(grosze: Int) -> Decimal { Decimal(grosze) / 100 }
}

extension Trip {
    /// "Wed, 4 Nov".
    func dateText(locale: Locale = Locale(identifier: "en_GB")) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).locale(locale)) + ", "
            + date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// "Sam · 6 items", "You & Sam · 18 items", "You · 4 items · no receipt".
    func metaText(me: Person) -> String {
        let people = shoppers
            .sorted { a, _ in a == me }
            .map { $0.displayName(me: me) }
            .joined(separator: " & ")
        let items = itemCount == 1 ? "1 item" : "\(itemCount) items"
        return [people, items, receiptImageID == nil ? "no receipt" : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// "74,20 zł", or an em dash when there is no total.
    var amountText: String { total.map(Money.pln) ?? "—" }

    var hasReceipt: Bool { receiptImageID != nil }
}
