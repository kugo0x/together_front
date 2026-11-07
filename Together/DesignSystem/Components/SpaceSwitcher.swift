import SwiftUI

/// The Shared ⇄ Personal pill. The thumb takes the selected space's fill and slides (240ms);
/// each segment has an icon + word so colour is never the only cue. `compact` for the nav bar.
struct SpaceSwitcher: View {
    @Binding var space: SpaceKind
    var compact = false

    @Namespace private var thumb
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @ScaledMetric(relativeTo: .subheadline) private var height: CGFloat = 32
    @ScaledMetric(relativeTo: .footnote) private var compactHeight: CGFloat = 28

    private let inset: CGFloat = 3

    var body: some View {
        EqualWidthHStack(minWidth: compact ? 0 : 196 - inset * 2) {
            segment(.shared, icon: .people, title: "Shared")
            segment(.personal, icon: .lock, title: "Personal")
        }
        .padding(inset)
        .background(TG.Colors.surface2, in: Capsule())
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Space")
    }

    private func segment(_ kind: SpaceKind, icon: IconName, title: String) -> some View {
        let selected = space == kind
        let accent = Accent.of(kind)
        let visualHeight = compact ? compactHeight : height
        return Button {
            withAnimation(.tg(.spring(duration: 0.24, bounce: 0), reduceMotion: reduceMotion)) { space = kind }
        } label: {
            HStack(spacing: TG.Space.s1) {
                Icon(icon)
                Text(title)
            }
            .font(compact ? TG.Font.footnote.weight(.semibold) : TG.Font.subhead.weight(.semibold))
            .lineLimit(1)
            .foregroundStyle(selected ? accent.on : TG.Colors.ink2)
            .padding(.horizontal, compact ? TG.Space.s2 : TG.Space.s3)
            .frame(maxWidth: .infinity, minHeight: visualHeight)
            .background {
                if selected {
                    if reduceMotion {
                        Capsule().fill(accent.fill)
                    } else {
                        Capsule().fill(accent.fill).matchedGeometryEffect(id: "thumb", in: thumb)
                    }
                }
            }
            .hitArea(visualHeight)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(title)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

// MARK: - Preview

struct SpaceSwitcherGallery: View {
    @State private var space: SpaceKind = .shared
    @State private var compactSpace: SpaceKind = .personal

    var body: some View {
        HStack(alignment: .center, spacing: TG.Space.s3) {
            VStack(alignment: .leading, spacing: TG.Space.s4) {
                SpaceSwitcher(space: $space)
                Text(space == .shared ? "Showing what Alex and Sam share." : "Showing only what is yours. Sam can’t see this.")
                    .font(TG.Font.subhead)
                    .foregroundStyle(TG.Colors.ink2)
                    .fixedSize()
            }
            .environment(\.space, space)
            SpaceSwitcher(space: $compactSpace, compact: true)
        }
        .padding(TG.Space.s4)
    }
}

#Preview("SpaceSwitcher · Light") { SpaceSwitcherGallery().catalogCanvas() }
#Preview("SpaceSwitcher · Dark") { SpaceSwitcherGallery().catalogCanvas().preferredColorScheme(.dark) }
