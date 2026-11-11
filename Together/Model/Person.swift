import SwiftUI

/// Someone in a space: a user ID from the API, their display name and which identity colour they get.
/// Equality is by ID only — a rename doesn't make someone else.
///
/// `.alex` and `.sam` are the prototype's two people (HANDOFF §4) and stay as the mock data, test fixtures and
/// `-signedIn YES` identities; signed in against the API, people come from `/v1/me` and the members list.
struct Person: Codable, Identifiable, Hashable, Sendable {
    /// The identity colour (`alex` / `sam` tokens). In a Shared space the owner gets the first, the partner the second.
    enum Tint: String, Codable, Sendable { case alex, sam }

    let id: UUID
    var name: String
    var tint: Tint

    init(id: UUID, name: String, tint: Tint) {
        self.id = id
        self.name = name
        self.tint = tint
    }

    static let alex = Person(id: UUID(uuidString: "0B0C6E0A-0000-4000-8000-00000000A1E0")!, name: "Alex", tint: .alex)
    static let sam = Person(id: UUID(uuidString: "0B0C6E0A-0000-4000-8000-0000000005A3")!, name: "Sam", tint: .sam)

    static func == (a: Person, b: Person) -> Bool { a.id == b.id }
    func hash(into hasher: inout Hasher) { hasher.combine(id) }

    var initial: String { name.first.map { String($0).uppercased() } ?? "?" }

    /// Identity colour. Avatars and the attribution dot only — never buttons or backgrounds.
    var color: Color {
        switch tint {
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
