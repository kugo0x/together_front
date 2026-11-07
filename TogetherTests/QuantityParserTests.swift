import Testing
@testable import Together

/// `parseQty` must behave like `parseQty` in design/design-system/components/bundle.js.
struct QuantityParserTests {
    @Test("Leading number or unit becomes the quantity", arguments: [
        ("2 oat milk", "oat milk", "2"),
        ("1 kg apples", "apples", "1 kg"),
        ("1kg apples", "apples", "1kg"),
        ("500 g coffee beans", "coffee beans", "500 g"),
        ("500g coffee", "coffee", "500g"),
        ("1,5 l water", "water", "1,5 l"),
        ("1.5 l water", "water", "1.5 l"),
        ("250 ml cream", "cream", "250 ml"),
        ("6 pack beer", "beer", "6 pack"),
        ("3x eggs", "eggs", "3"),
        ("3X eggs", "eggs", "3"),
        ("2 x eggs", "eggs", "2"),
        ("2 KG potatoes", "potatoes", "2 KG"),
        ("10 eggs", "eggs", "10"),
        ("  2   oat milk  ", "oat milk", "2"),
        ("2 gala apples", "gala apples", "2"),
        ("2 lemons", "lemons", "2"),
        ("2 1 kg", "1 kg", "2"),
    ])
    func parsesQuantity(input: String, name: String, qty: String) {
        #expect(QuantityParser.parseQty(input) == ParsedQuantity(name: name, qty: qty))
    }

    @Test("No leading quantity keeps everything as the name", arguments: [
        ("milk", "milk"),
        ("Oat milk", "Oat milk"),
        ("  bread  ", "bread"),
        ("2", "2"),
        ("2kg", "2kg"),
        ("eggs 10", "eggs 10"),
        ("7up", "7up"),
        ("", ""),
    ])
    func noQuantity(input: String, name: String) {
        #expect(QuantityParser.parseQty(input) == ParsedQuantity(name: name, qty: nil))
    }

    @Test func quickAddCapitalisesName() {
        #expect(QuantityParser.groceryInput("2 oat milk") == ParsedQuantity(name: "Oat milk", qty: "2"))
        #expect(QuantityParser.groceryInput("tomatoes") == ParsedQuantity(name: "Tomatoes", qty: nil))
        #expect(QuantityParser.groceryInput("1 kg apples") == ParsedQuantity(name: "Apples", qty: "1 kg"))
        #expect(QuantityParser.groceryInput("łosoś") == ParsedQuantity(name: "Łosoś", qty: nil))
    }

    @Test func quickAddIgnoresBlankInput() {
        #expect(QuantityParser.groceryInput("") == nil)
        #expect(QuantityParser.groceryInput("   \n ") == nil)
    }
}
