import SwiftUI
import UIKit

/// Component dimensions from `design/design-system/components/bundle.css` that are not
/// spacing / radius tokens (control heights, glyph boxes). Everything else comes from `TG`.
enum DS {
    /// Minimum hit target for any control (HANDOFF §2.8).
    static let minTarget: CGFloat = 44
    /// Check circle in rows (`.tg-check`).
    static let checkSize: CGFloat = 26
    static let checkStroke: CGFloat = 1.75
    /// Row minimum height: `space-3` × 2 + 22pt line.
    static let rowMinHeight: CGFloat = 46
    /// Separator inset for rows that start with a check circle (`.tg-row + .tg-row::before { left: 52px }`).
    static let checkRowSeparatorInset: CGFloat = 52
    /// Gap between a row title and its metadata line. CSS uses 2px plus taller line boxes
    /// (22/18px) than SF's natural line heights; 4pt keeps the row height within ~2pt of the reference.
    static let rowLineGap: CGFloat = 4
    static let hairline: CGFloat = 1
    /// Uppercase badge tracking: 0.04em of the 12pt caption.
    static let captionTracking: CGFloat = 0.48
    /// Opacity of disabled controls.
    static let disabledOpacity: Double = 0.4
}

// MARK: - Shadows

extension TG {
    /// `shadow-sheet` / `shadow-float` from tokens.json (not part of the generated Tokens.swift).
    /// CSS blur is twice SwiftUI's radius.
    enum Shadow {
        struct Spec: Sendable {
            let color: Color
            let radius: CGFloat
            let y: CGFloat
        }

        /// `0 -8px 32px` — bottom sheets only.
        static let sheet = Spec(color: shadowColor(light: 0.12, dark: 0.5), radius: 16, y: -8)
        /// `0 6px 20px` — toast and other floating elements.
        static let float = Spec(color: shadowColor(light: 0.16, dark: 0.55), radius: 10, y: 6)

        /// Light shadows are tinted with `ink` (rgba(28,26,23,a)); dark ones are black.
        private static func shadowColor(light: CGFloat, dark: CGFloat) -> Color {
            Color(UIColor { traits in
                if traits.userInterfaceStyle == .dark {
                    return UIColor.black.withAlphaComponent(dark)
                }
                return UIColor(TG.Colors.ink)
                    .resolvedColor(with: UITraitCollection(userInterfaceStyle: .light))
                    .withAlphaComponent(light)
            })
        }
    }
}

extension View {
    func tgShadow(_ spec: TG.Shadow.Spec) -> some View {
        shadow(color: spec.color, radius: spec.radius, x: 0, y: spec.y)
    }

    /// Grows the tappable area of a small control (`visual` = its drawn size) to 44×44
    /// without changing layout.
    func hitArea(_ visual: CGFloat) -> some View {
        contentShape(Rectangle().inset(by: -max(0, (DS.minTarget - visual) / 2)))
    }
}

/// A button style that draws the label as-is (no system dimming or highlight) — for controls that
/// handle their own pressed / disabled look.
struct BareButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View { configuration.label }
}

extension ButtonStyle where Self == BareButtonStyle {
    static var bare: BareButtonStyle { BareButtonStyle() }
}

// MARK: - Motion

extension Animation {
    /// Movement when allowed, a 150ms fade under Reduce Motion (README › Motion and states).
    static func tg(_ animation: Animation, reduceMotion: Bool) -> Animation {
        reduceMotion ? .easeInOut(duration: 0.15) : animation
    }
}
