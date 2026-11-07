import SwiftUI

/// Exactly four tabs. Settings is reached from the Avatar, Search by pulling down a list.
enum AppTab: String, CaseIterable, Identifiable, Sendable {
    case home, groceries, tasks, notes

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: "Home"
        case .groceries: "Groceries"
        case .tasks: "Tasks"
        case .notes: "Notes"
        }
    }

    var icon: IconName {
        switch self {
        case .home: .home
        case .groceries: .cart
        case .tasks: .tasks
        case .notes: .note
        }
    }
}

/// The design-system tab bar: current tab in the space text accent, others `ink-3` icons with `ink-2` labels.
///
/// The app shell should use a native `TabView` with `.tint(accent.ink)` and `AppTab` for titles/icons
/// (HANDOFF §3); this view is the static version for compositions and previews.
struct TabBar: View {
    @Binding var selection: AppTab

    @Environment(\.accent) private var accent

    var body: some View {
        HStack(spacing: 0) {
            ForEach(AppTab.allCases) { tab in
                let selected = tab == selection
                Button {
                    selection = tab
                } label: {
                    VStack(spacing: DS.rowLineGap) {
                        Icon(tab.icon)
                            .font(TG.Font.title3.weight(selected ? .semibold : .regular))
                            .foregroundStyle(selected ? accent.ink : TG.Colors.ink3)
                            .frame(height: 28)
                        Text(tab.title)
                            .font(TG.Font.tabLabel)
                            .foregroundStyle(selected ? accent.ink : TG.Colors.ink2)
                    }
                    .frame(maxWidth: .infinity, minHeight: DS.minTarget)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(tab.title)
                .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
            }
        }
        .padding(.top, 6)
        .padding(.bottom, 22)
        .background(TG.Colors.surface)
        .overlay(alignment: .top) {
            TG.Colors.separator.frame(height: DS.hairline)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Tabs")
    }
}

// MARK: - Preview

struct TabBarGallery: View {
    @State private var tab: AppTab = .groceries

    var body: some View {
        TabBar(selection: $tab)
            .frame(width: 390)
    }
}

#Preview("TabBar · Light") { TabBarGallery().catalogCanvas() }
#Preview("TabBar · Dark") { TabBarGallery().catalogCanvas().preferredColorScheme(.dark) }
