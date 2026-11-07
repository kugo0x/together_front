import Foundation

/// Result of splitting quick-add text into a grocery name and quantity.
struct ParsedQuantity: Equatable, Sendable {
    var name: String
    var qty: String?
}

/// Port of `parseQty` from `design/design-system/components/bundle.js`.
///
/// A leading number with an optional unit (`kg`, `g`, `l`, `ml`, `pack`, `x`) followed by whitespace
/// becomes the quantity: "2 oat milk" → qty "2", name "oat milk"; "1 kg apples" → "1 kg", "apples";
/// "3x eggs" → "3", "eggs". Anything else is all name.
enum QuantityParser {
    // Same pattern and flags as the JS: /^(\d+(?:[.,]\d+)?\s?(?:kg|g|l|ml|pack|x)?)\s+(.+)$/i
    private static let pattern = try! NSRegularExpression(
        pattern: #"^([0-9]+(?:[.,][0-9]+)?\s?(?:kg|g|l|ml|pack|x)?)\s+(.+)$"#,
        options: [.caseInsensitive]
    )

    /// Exact port: trims, splits, strips a trailing `x` from the quantity ("3x" → "3").
    /// Unlike the JS, also trims the quantity so "2 x eggs" gives "2", not "2 ".
    static func parseQty(_ text: String) -> ParsedQuantity {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        let range = NSRange(trimmed.startIndex..., in: trimmed)
        guard
            let match = pattern.firstMatch(in: trimmed, range: range),
            let qtyRange = Range(match.range(at: 1), in: trimmed),
            let nameRange = Range(match.range(at: 2), in: trimmed)
        else {
            return ParsedQuantity(name: trimmed, qty: nil)
        }
        var qty = String(trimmed[qtyRange])
        if qty.last == "x" || qty.last == "X" { qty.removeLast() }
        qty = qty.trimmingCharacters(in: .whitespaces)
        return ParsedQuantity(name: String(trimmed[nameRange]), qty: qty)
    }

    /// What QuickAdd submits: `nil` for blank input, otherwise `parseQty` with the name's
    /// first letter capitalised ("2 oat milk" → "Oat milk", "2").
    static func groceryInput(_ text: String) -> ParsedQuantity? {
        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        var result = parseQty(text)
        if let first = result.name.first {
            result.name = first.uppercased() + result.name.dropFirst()
        }
        return result
    }
}
