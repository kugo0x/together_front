import SwiftUI

/// The two people in the prototype (HANDOFF §4). In the real app these become user IDs;
/// the design system only needs a name, an initial and an identity colour.
enum Person: String, Codable, CaseIterable, Identifiable, Sendable {
    case alex, sam

    var id: String { rawValue }

    var name: String {
        switch self {
        case .alex: "Alex"
        case .sam: "Sam"
        }
    }

    var initial: String { String(name.prefix(1)) }

    /// Identity colour (`alex` / `sam` tokens). Avatars and the attribution dot only — never buttons or backgrounds.
    var color: Color {
        switch self {
        case .alex: TG.Colors.alex
        case .sam: TG.Colors.sam
        }
    }

    /// "You" for the signed-in person, the name otherwise ("Sam bought this", "You did this").
    func displayName(me: Person = .alex) -> String {
        self == me ? "You" : name
    }
}

/// A weekly grocery suggestion computed from purchase history (HANDOFF §4).
struct Suggestion: Identifiable, Hashable, Sendable {
    var id: String { name }
    var name: String
    var qty: String?
    var reason: String
}
