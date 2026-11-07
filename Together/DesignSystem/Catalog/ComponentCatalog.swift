import SwiftUI

/// Every design-system component with the gallery that mirrors its `preview.html` in
/// `design/design-system/components/<Name>/`. Used by the catalog screen and by the snapshot test,
/// which renders each gallery at the reference screenshot's size for comparison.
struct CatalogEntry: Identifiable {
    let name: String
    /// Point size of `design/screenshots/components/<name>-light.png` (rendered @2x).
    let canvas: CGSize
    let view: @MainActor () -> AnyView

    var id: String { name }
}

enum ComponentCatalog {
    @MainActor static let entries: [CatalogEntry] = [
        entry("Icon", 520, 200) { IconGallery() },
        entry("Avatar", 520, 200) { AvatarGallery() },
        entry("SpaceSwitcher", 520, 200) { SpaceSwitcherGallery() },
        entry("PrivacyBadge", 520, 200) { PrivacyBadgeGallery() },
        entry("Button", 520, 210) { ButtonGallery() },
        entry("NavBar", 520, 200) { NavBarGallery() },
        entry("TabBar", 520, 200) { TabBarGallery() },
        entry("SectionHeader", 520, 200) { SectionHeaderGallery() },
        entry("QuickAdd", 520, 200) { QuickAddGallery() },
        entry("GroceryItem", 520, 299) { GroceryItemGallery() },
        entry("TaskRow", 520, 364) { TaskRowGallery() },
        entry("NoteRow", 520, 360) { NoteRowGallery() },
        entry("SuggestionCard", 520, 325) { SuggestionCardGallery() },
        entry("EmptyState", 520, 283) { EmptyStateGallery() },
        entry("Toast", 520, 200) { ToastGallery() },
        entry("ConfirmSheet", 520, 340) { ConfirmSheetGallery() },
        entry("Chip", 520, 200) { ChipGallery() },
        entry("NotificationPreview", 520, 200) { NotificationPreviewGallery() },
        entry("ReceiptLine", 520, 382) { ReceiptLineGallery() },
        entry("Cover", 960, 288) { CoverGallery() },
    ]

    @MainActor private static func entry<V: View>(
        _ name: String, _ width: CGFloat, _ height: CGFloat, @ViewBuilder _ view: @escaping @MainActor () -> V
    ) -> CatalogEntry {
        CatalogEntry(name: name, canvas: CGSize(width: width, height: height)) { AnyView(view()) }
    }
}

extension View {
    /// Places a gallery top-leading on the `bg` canvas, like the reference screenshots.
    func catalogCanvas() -> some View {
        frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(TG.Colors.bg)
    }
}

/// Browsable list of all components — the app's root until the shell lands (Phase 2).
struct ComponentCatalogView: View {
    @State private var space: SpaceKind = .shared

    var body: some View {
        NavigationStack {
            List(ComponentCatalog.entries) { entry in
                NavigationLink(entry.name) {
                    ScrollView([.horizontal, .vertical]) {
                        entry.view()
                    }
                    .background(TG.Colors.bg)
                    .navigationTitle(entry.name)
                    .navigationBarTitleDisplayMode(.inline)
                }
                .font(TG.Font.body)
                .foregroundStyle(TG.Colors.ink)
                .listRowBackground(TG.Colors.surface)
            }
            .scrollContentBackground(.hidden)
            .background(TG.Colors.bg)
            .togetherNavigation(title: "Components", space: $space, onAvatar: {})
        }
        .tint(Accent.of(space).ink)
        .environment(\.space, space)
    }
}

#Preview("Catalog") { ComponentCatalogView() }
