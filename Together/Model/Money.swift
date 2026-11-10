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

    /// "78,40" — for editable fields (the "zł" sits beside them).
    static func number(_ amount: Decimal) -> String { amount.formatted(style) }

    /// A quantity with a comma decimal: 2 → "2" (0 digits), 1.02 kg → "1,020" (3 digits).
    static func number(_ amount: Decimal, fractionDigits: Int) -> String {
        amount.formatted(.number.precision(.fractionLength(fractionDigits)).locale(Locale(identifier: "pl_PL")))
    }

    /// What someone typed: "78,4", "78.40", "1 234,50" → 78.4 / 1234.5; `nil` for empty or not a number.
    static func parse(_ text: String) -> Decimal? {
        let cleaned = text.filter { !$0.isWhitespace && $0 != "\u{00A0}" && $0 != "\u{202F}" }
            .replacingOccurrences(of: "zł", with: "")
            .replacingOccurrences(of: ",", with: ".")
        guard !cleaned.isEmpty, cleaned.filter({ $0 == "." }).count <= 1,
              cleaned.allSatisfy({ $0.isNumber || $0 == "." }) else { return nil }
        return Decimal(string: cleaned, locale: Locale(identifier: "en_US_POSIX"))
    }
}

extension Trip {
    /// "Wed, 4 Nov".
    func dateText(locale: Locale = Locale(identifier: "en_GB")) -> String {
        date.formatted(.dateTime.weekday(.abbreviated).locale(locale)) + ", "
            + date.formatted(.dateTime.day().month(.abbreviated).locale(locale))
    }

    /// "Biedronka · You · 8 items", "Sam · 6 items", "You & Sam · 18 items", "You · 4 items · no receipt".
    func metaText(me: Person) -> String {
        let people = shoppers
            .sorted { a, _ in a == me }
            .map { $0.displayName(me: me) }
            .joined(separator: " & ")
        let items = itemCount == 1 ? "1 item" : "\(itemCount) items"
        return [merchant, people, items, receiptImageID == nil ? "no receipt" : nil]
            .compactMap { $0 }
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
    }

    /// "74,20 zł", or an em dash when there is no total.
    var amountText: String { total.map(Money.pln) ?? "—" }

    var hasReceipt: Bool { receiptImageID != nil }
}
