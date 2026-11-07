import SwiftUI

/// The app shell: four tabs, each a large-title navigation stack with the avatar (→ Settings) leading and
/// the space switcher trailing. Owns the global space (persisted), the store and the toast centre.
struct RootView: View {
    @AppStorage(SpaceSetting.key) private var space: SpaceKind = SpaceSetting.defaultValue
    @State private var tab: AppTab = RootView.launchTab
    @State private var store: AppStore
    @State private var toasts = ToastCenter()
    @State private var showSettings = false

    init(store: AppStore = AppStore()) {
        _store = State(initialValue: store)
    }

    var body: some View {
        TabView(selection: $tab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    screen(for: tab)
                        .togetherNavigation(title: title(for: tab), me: store.me, space: $space) {
                            showSettings = true
                        }
                        .toastHost()
                }
                .tabItem { Label(tab.title, systemImage: tab.icon.systemName) }
                .tag(tab)
            }
        }
        .tint(Accent.of(space).ink)
        .sheet(isPresented: $showSettings) { SettingsPlaceholder() }
        .task {
            // `-demoToast YES` (launch argument) shows a toast on launch — for screenshots of the overlay.
            if UserDefaults.standard.bool(forKey: "demoToast") {
                toasts.show("Sam bought Tomatoes", person: .sam)
            }
        }
        .environment(\.space, space)
        .environment(store)
        .environment(toasts)
    }

    @ViewBuilder
    private func screen(for tab: AppTab) -> some View {
        switch tab {
        case .home: HomeScreen()
        case .groceries: GroceriesScreen()
        case .tasks: TasksScreen()
        case .notes: NotesScreen()
        }
    }

    /// Home is titled with the space name; the other tabs keep their own name.
    private func title(for tab: AppTab) -> String {
        tab == .home ? space.displayName : tab.title
    }

    /// `-initialTab groceries` (launch argument) opens a tab directly — for screenshots and UI checks.
    private static var launchTab: AppTab {
        UserDefaults.standard.string(forKey: "initialTab").flatMap(AppTab.init(rawValue:)) ?? .home
    }
}

extension SpaceKind {
    var displayName: String {
        switch self {
        case .shared: "Shared"
        case .personal: "Personal"
        }
    }
}

#Preview("Shell · Light") { RootView() }
#Preview("Shell · Dark") { RootView().preferredColorScheme(.dark) }
#Preview("Shell · Personal") { RootView().defaultAppStorage(UserDefaults(suiteName: "preview.personal")!) }
