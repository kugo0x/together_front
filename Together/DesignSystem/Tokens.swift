// Together — design tokens for SwiftUI.
// GENERATED from design/design-system/tokens.json. Do not edit by hand; regenerate when tokens change.
import SwiftUI
import UIKit

private func dynamic(_ light: UIColor, _ dark: UIColor) -> Color {
    Color(UIColor { $0.userInterfaceStyle == .dark ? dark : light })
}

enum TG {
    enum Colors {
        /// Screen background behind grouped sections. Warm paper in light, near-black in dark.
        static let bg = dynamic(UIColor(red: 0.965, green: 0.957, blue: 0.941, alpha: 1.00), UIColor(red: 0.059, green: 0.055, blue: 0.051, alpha: 1.00))
        /// Grouped section and row fill, sheets, the quick-add field.
        static let surface = dynamic(UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.00), UIColor(red: 0.110, green: 0.106, blue: 0.098, alpha: 1.00))
        /// Sunken fills: segmented-control track, search field, pressed rows, quantity stepper.
        static let surface2 = dynamic(UIColor(red: 0.937, green: 0.925, blue: 0.906, alpha: 1.00), UIColor(red: 0.153, green: 0.145, blue: 0.137, alpha: 1.00))
        /// Primary text and titles on bg, surface and surface-2 (≥14.7:1 both themes).
        static let ink = dynamic(UIColor(red: 0.110, green: 0.102, blue: 0.090, alpha: 1.00), UIColor(red: 0.953, green: 0.937, blue: 0.914, alpha: 1.00))
        /// Secondary text — metadata, quantities, timestamps, note previews — on bg and surface (≥5.3:1 both themes).
        static let ink2 = dynamic(UIColor(red: 0.416, green: 0.392, blue: 0.361, alpha: 1.00), UIColor(red: 0.647, green: 0.624, blue: 0.588, alpha: 1.00))
        /// Non-text only: chevrons, unchecked circle strokes, inactive tab icons (≥3.2:1). Never for words, placeholders included — use ink-2.
        static let ink3 = dynamic(UIColor(red: 0.549, green: 0.525, blue: 0.490, alpha: 1.00), UIColor(red: 0.478, green: 0.455, blue: 0.424, alpha: 1.00))
        /// Hairline between rows inside a section, inset to the text column. Decorative; never the only boundary of a control.
        static let separator = dynamic(UIColor(red: 0.902, green: 0.886, blue: 0.863, alpha: 1.00), UIColor(red: 0.184, green: 0.173, blue: 0.161, alpha: 1.00))
        /// The Shared space. Fills: space pill, primary buttons and checkmarks inside Shared, the quick-add send button. Pair with on-shared.
        static let shared = dynamic(UIColor(red: 0.769, green: 0.314, blue: 0.173, alpha: 1.00), UIColor(red: 0.949, green: 0.510, blue: 0.373, alpha: 1.00))
        /// Shared accent as text and icons on surface, bg and shared-soft — links, 'Add', section actions (≥4.8:1 both themes).
        static let sharedInk = dynamic(UIColor(red: 0.698, green: 0.271, blue: 0.141, alpha: 1.00), UIColor(red: 0.949, green: 0.510, blue: 0.373, alpha: 1.00))
        /// Shared tint: suggestion card ground, selected-row wash, the Shared badge ground. Text on it is ink or shared-ink.
        static let sharedSoft = dynamic(UIColor(red: 0.984, green: 0.918, blue: 0.890, alpha: 1.00), UIColor(red: 0.227, green: 0.133, blue: 0.098, alpha: 1.00))
        /// Text and icons on a shared fill. Dark in dark mode because the coral lightens (4.6:1 light, 6.7:1 dark).
        static let onShared = dynamic(UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.00), UIColor(red: 0.110, green: 0.102, blue: 0.090, alpha: 1.00))
        /// The Personal space. Same roles as shared — pill, primary buttons, checkmarks — whenever Personal is the active space. Also its text accent (≥6.8:1 on surface).
        static let personal = dynamic(UIColor(red: 0.231, green: 0.357, blue: 0.549, alpha: 1.00), UIColor(red: 0.576, green: 0.698, blue: 0.890, alpha: 1.00))
        /// Personal tint: the Private badge ground, the privacy banner in the note editor.
        static let personalSoft = dynamic(UIColor(red: 0.910, green: 0.933, blue: 0.969, alpha: 1.00), UIColor(red: 0.106, green: 0.141, blue: 0.196, alpha: 1.00))
        /// Text and icons on a personal fill (6.9:1 light, 8.2:1 dark).
        static let onPersonal = dynamic(UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.00), UIColor(red: 0.078, green: 0.094, blue: 0.122, alpha: 1.00))
        /// Confirmation glyphs and the 'Bought' count. Always with a word or check icon, never colour alone.
        static let success = dynamic(UIColor(red: 0.180, green: 0.478, blue: 0.306, alpha: 1.00), UIColor(red: 0.388, green: 0.769, blue: 0.553, alpha: 1.00))
        /// Due today / overdue labels on surface (≥5.5:1). Always with the date as text.
        static let warning = dynamic(UIColor(red: 0.604, green: 0.345, blue: 0.000, alpha: 1.00), UIColor(red: 0.941, green: 0.706, blue: 0.298, alpha: 1.00))
        /// Destructive actions only — Delete, Remove partner — always as a labelled button.
        static let danger = dynamic(UIColor(red: 0.706, green: 0.137, blue: 0.094, alpha: 1.00), UIColor(red: 1.000, green: 0.420, blue: 0.369, alpha: 1.00))
        /// Alex's avatar fill and completion attribution dot. Initials in on-person.
        static let alex = dynamic(UIColor(red: 0.247, green: 0.478, blue: 0.369, alpha: 1.00), UIColor(red: 0.498, green: 0.722, blue: 0.604, alpha: 1.00))
        /// Sam's avatar fill and completion attribution dot. Initials in on-person.
        static let sam = dynamic(UIColor(red: 0.580, green: 0.376, blue: 0.059, alpha: 1.00), UIColor(red: 0.878, green: 0.667, blue: 0.310, alpha: 1.00))
        /// Avatar initials on alex and sam (≥5:1 both themes).
        static let onPerson = dynamic(UIColor(red: 1.000, green: 1.000, blue: 1.000, alpha: 1.00), UIColor(red: 0.078, green: 0.094, blue: 0.122, alpha: 1.00))
        /// Dimmed backdrop behind sheets and confirmation dialogs.
        static let scrim = dynamic(UIColor(red: 0.110, green: 0.102, blue: 0.090, alpha: 0.32), UIColor(red: 0.000, green: 0.000, blue: 0.000, alpha: 0.56))
        /// Toast pill fill — inverted ink. Text on it is on-toast.
        static let toast = dynamic(UIColor(red: 0.110, green: 0.102, blue: 0.090, alpha: 1.00), UIColor(red: 0.953, green: 0.937, blue: 0.914, alpha: 1.00))
        /// Text on toast (≥15:1).
        static let onToast = dynamic(UIColor(red: 0.965, green: 0.957, blue: 0.941, alpha: 1.00), UIColor(red: 0.110, green: 0.102, blue: 0.090, alpha: 1.00))
        /// Keyboard focus ring: 2px solid, 2px offset, on every surface (≥14:1).
        static let focus = dynamic(UIColor(red: 0.110, green: 0.102, blue: 0.090, alpha: 1.00), UIColor(red: 0.953, green: 0.937, blue: 0.914, alpha: 1.00))
    }

    enum Space {
        /// Icon-to-label gap inside badges; avatar overlap offset.
        static let s1: CGFloat = 4
        /// Gap between a row's title and metadata; chip gaps.
        static let s2: CGFloat = 8
        /// Row vertical padding (with 22px text this gives a 46px row, 44pt+ target); icon-to-text gap in rows.
        static let s3: CGFloat = 12
        /// Screen side gutter and row horizontal padding — the iOS inset.
        static let s4: CGFloat = 16
        /// Inside sheets and cards.
        static let s5: CGFloat = 20
        /// Gap between grouped sections.
        static let s6: CGFloat = 24
        /// Empty-state padding; space above a large title.
        static let s8: CGFloat = 32
    }

    enum Radius {
        /// Badges, quantity stepper, search field.
        static let sm: CGFloat = 8
        /// Buttons, the quick-add field, segmented control segments.
        static let md: CGFloat = 12
        /// Grouped sections and the suggestion card.
        static let lg: CGFloat = 16
        /// Sheet top corners, onboarding illustration tiles.
        static let xl: CGFloat = 24
        /// Space pill, avatars, toast, checkbox circles.
        static let full: CGFloat = 999
    }

    /// Type scale = iOS Dynamic Type text styles. Use these, never fixed point sizes.
    enum Font {
        /// 34px/41px 700 — One per screen: the space or tab title in the large nav bar.
        static let largeTitle: SwiftUI.Font = .largeTitle.weight(.bold)
        /// 22px/28px 700 — Note title in the editor; onboarding headlines.
        static let title2: SwiftUI.Font = .title2.weight(.bold)
        /// 20px/25px 600 — Home greeting, sheet titles.
        static let title3: SwiftUI.Font = .title3.weight(.semibold)
        /// 17px/22px 600 — Section titles on Home, row titles that need weight (note titles).
        static let headline: SwiftUI.Font = .headline
        /// 17px/22px 400 — Row text for grocery items and tasks; editor body.
        static let body: SwiftUI.Font = .body
        /// 16px/21px 400 — Suggestion copy, empty-state body.
        static let callout: SwiftUI.Font = .callout
        /// 15px/20px 400 — Compact rows on Home, segmented control labels (600).
        static let subhead: SwiftUI.Font = .subheadline
        /// 13px/18px 400 — Metadata under a row: attribution, due date, quantity hint.
        static let footnote: SwiftUI.Font = .footnote
        /// 12px/16px 500 — Badges and section eyebrows, uppercase with 0.04em tracking.
        static let caption: SwiftUI.Font = .caption.weight(.medium)
        /// 10px/12px 500 — Tab bar labels only.
        static let tabLabel: SwiftUI.Font = .caption2.weight(.medium)
        /// Avatar initials and onboarding wordmark.
        static func rounded(_ size: CGFloat) -> SwiftUI.Font { .system(size: size, weight: .bold, design: .rounded) }
    }
}

/// Active-space accent: Shared = coral, Personal = slate. Inject once at the root with .environment(\.space, ...).
enum SpaceKind: String, Codable { case shared, personal }

struct Accent {
    let fill: Color, ink: Color, soft: Color, on: Color
    static func of(_ s: SpaceKind) -> Accent {
        s == .shared
            ? Accent(fill: TG.Colors.shared, ink: TG.Colors.sharedInk, soft: TG.Colors.sharedSoft, on: TG.Colors.onShared)
            : Accent(fill: TG.Colors.personal, ink: TG.Colors.personal, soft: TG.Colors.personalSoft, on: TG.Colors.onPersonal)
    }
}

private struct SpaceKey: EnvironmentKey { static let defaultValue: SpaceKind = .shared }
extension EnvironmentValues {
    var space: SpaceKind { get { self[SpaceKey.self] } set { self[SpaceKey.self] = newValue } }
    var accent: Accent { Accent.of(space) }
}
