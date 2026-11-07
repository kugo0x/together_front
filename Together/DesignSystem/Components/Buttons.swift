import SwiftUI

/// Button variants from the design system, tinted by the active space (`\.space`).
/// - primary: the one main action (space fill) · tinted: secondary on a surface · secondary: Cancel/Skip
/// - plain: nav-bar text actions · destructive: labelled delete only
/// Sizes: `.md` 50pt block, `.sm` 34pt capsule for inline rows.
struct TGButtonStyle: ButtonStyle {
    enum Variant: Sendable { case primary, tinted, secondary, plain, destructive }
    enum Size: Sendable { case md, sm }

    var variant: Variant = .primary
    var size: Size = .md
    /// Fill the available width (`block`).
    var block = false
    /// Overrides the neutral fill of `secondary` (the suggestion card puts Skip on `surface`).
    var secondaryFill: Color?

    func makeBody(configuration: Configuration) -> some View {
        TGButtonBody(configuration: configuration, style: self)
    }
}

private struct TGButtonBody: View {
    let configuration: ButtonStyleConfiguration
    let style: TGButtonStyle

    @Environment(\.accent) private var accent
    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .headline) private var mdHeight: CGFloat = 50
    @ScaledMetric(relativeTo: .subheadline) private var smHeight: CGFloat = 34

    private var isSmall: Bool { style.size == .sm }

    var body: some View {
        configuration.label
            .labelStyle(TGButtonLabelStyle())
            .font(isSmall ? TG.Font.subhead.weight(.semibold) : TG.Font.headline)
            .lineLimit(2)
            .multilineTextAlignment(.center)
            .foregroundStyle(foreground)
            .padding(.horizontal, horizontalPadding)
            .frame(maxWidth: style.block ? .infinity : nil, minHeight: isSmall ? smHeight : mdHeight)
            .background(background, in: shape)
            .contentShape(shape)
            .hitArea(isSmall ? smHeight : mdHeight)
            .opacity(isEnabled ? 1 : DS.disabledOpacity)
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .opacity(configuration.isPressed && reduceMotion ? 0.7 : 1)
            .animation(.easeOut(duration: 0.08), value: configuration.isPressed)
    }

    private var shape: AnyShape {
        isSmall ? AnyShape(Capsule()) : AnyShape(RoundedRectangle(cornerRadius: TG.Radius.md, style: .continuous))
    }

    private var horizontalPadding: CGFloat {
        if style.variant == .plain { return TG.Space.s2 }
        return isSmall ? TG.Space.s3 : TG.Space.s5
    }

    private var foreground: Color {
        switch style.variant {
        case .primary: accent.on
        case .tinted, .plain: accent.ink
        case .secondary: TG.Colors.ink
        case .destructive: TG.Colors.danger
        }
    }

    private var background: Color {
        switch style.variant {
        case .primary: accent.fill
        case .tinted: accent.soft
        case .secondary: style.secondaryFill ?? TG.Colors.surface2
        case .destructive: TG.Colors.surface2
        case .plain: .clear
        }
    }
}

/// Icon + title with `space-2` between them (icon follows the label's font).
private struct TGButtonLabelStyle: LabelStyle {
    func makeBody(configuration: Configuration) -> some View {
        HStack(spacing: TG.Space.s2) {
            configuration.icon
            configuration.title
        }
    }
}

extension ButtonStyle where Self == TGButtonStyle {
    static var tgPrimary: TGButtonStyle { TGButtonStyle(variant: .primary) }
    static var tgTinted: TGButtonStyle { TGButtonStyle(variant: .tinted) }
    static var tgSecondary: TGButtonStyle { TGButtonStyle(variant: .secondary) }
    static var tgPlain: TGButtonStyle { TGButtonStyle(variant: .plain) }
    static var tgDestructive: TGButtonStyle { TGButtonStyle(variant: .destructive) }

    static func tg(
        _ variant: TGButtonStyle.Variant,
        size: TGButtonStyle.Size = .md,
        block: Bool = false,
        secondaryFill: Color? = nil
    ) -> TGButtonStyle {
        TGButtonStyle(variant: variant, size: size, block: block, secondaryFill: secondaryFill)
    }
}

/// Convenience for the common "title + optional icon" button.
struct TGButton: View {
    let title: String
    var icon: IconName?
    var variant: TGButtonStyle.Variant = .primary
    var size: TGButtonStyle.Size = .md
    var block = false
    let action: () -> Void

    init(
        _ title: String,
        icon: IconName? = nil,
        variant: TGButtonStyle.Variant = .primary,
        size: TGButtonStyle.Size = .md,
        block: Bool = false,
        action: @escaping () -> Void
    ) {
        self.title = title
        self.icon = icon
        self.variant = variant
        self.size = size
        self.block = block
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            if let icon {
                Label { Text(title) } icon: { Icon(icon) }
            } else {
                Text(title)
            }
        }
        .buttonStyle(.tg(variant, size: size, block: block))
    }
}

// MARK: - Preview

struct ButtonGallery: View {
    var body: some View {
        VStack(alignment: .leading, spacing: TG.Space.s4) {
            FlowLayout(spacing: TG.Space.s3, lineSpacing: TG.Space.s3) {
                TGButton("Add task", icon: .plus) {}
                TGButton("Invite Sam", variant: .tinted) {}
                TGButton("Cancel", variant: .secondary) {}
                TGButton("Done", variant: .plain) {}
                TGButton("Delete", icon: .trash, variant: .destructive) {}
            }
            FlowLayout(spacing: TG.Space.s3, lineSpacing: TG.Space.s3) {
                TGButton("New private note", icon: .plus) {}
                TGButton("Add", variant: .tinted, size: .sm) {}
                TGButton("Add", icon: .plus, size: .sm) {}
            }
            .environment(\.space, .personal)
        }
        .padding(TG.Space.s4)
    }
}

#Preview("Button · Light") { ButtonGallery().catalogCanvas() }
#Preview("Button · Dark") { ButtonGallery().catalogCanvas().preferredColorScheme(.dark) }
