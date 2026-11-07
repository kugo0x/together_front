import SwiftUI

/// The large-title header every tab starts with: avatar leading (→ Settings), compact SpaceSwitcher
/// trailing, large title, one quiet subtitle line. Sits on `bg`.
///
/// For real screens prefer the native bar via `.togetherNavigation(...)` below (HANDOFF §3);
/// this view is the static version used in compositions and previews.
struct NavBar<Leading: View, Trailing: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var leading: Leading
    @ViewBuilder var trailing: Trailing

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: TG.Space.s3) {
                leading
                Spacer(minLength: 0)
                trailing
            }
            .frame(minHeight: DS.minTarget)

            Text(title)
                .font(TG.Font.largeTitle)
                .foregroundStyle(TG.Colors.ink)
                .padding(.top, TG.Space.s1)
                .accessibilityAddTraits(.isHeader)

            if let subtitle {
                Text(subtitle)
                    .font(TG.Font.subhead)
                    .foregroundStyle(TG.Colors.ink2)
                    .padding(.top, DS.rowLineGap)
            }
        }
        .padding(.horizontal, TG.Space.s4)
        .padding(.vertical, TG.Space.s2)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(TG.Colors.bg)
    }
}

extension View {
    /// Native large-title navigation with the avatar (→ Settings) leading and the compact space switcher trailing.
    func togetherNavigation(
        title: String,
        me: Person = .alex,
        space: Binding<SpaceKind>,
        onAvatar: @escaping () -> Void
    ) -> some View {
        navigationTitle(title)
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button(action: onAvatar) { Avatar(person: me, size: 32) }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Settings")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    SpaceSwitcher(space: space, compact: true)
                }
            }
    }
}

// MARK: - Preview

struct NavBarGallery: View {
    @State private var space: SpaceKind = .shared

    var body: some View {
        NavBar(title: "Groceries", subtitle: "7 to buy · Sam added 2 today") {
            Avatar(person: .alex, size: 32)
        } trailing: {
            SpaceSwitcher(space: $space, compact: true)
        }
        .frame(width: 390)
    }
}

#Preview("NavBar · Light") { NavBarGallery().catalogCanvas() }
#Preview("NavBar · Dark") { NavBarGallery().catalogCanvas().preferredColorScheme(.dark) }
