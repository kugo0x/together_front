import SwiftUI

/// The app shell: four tabs, each a large-title navigation stack with the avatar (→ Settings) leading and
/// the space switcher trailing. Owns the global space (persisted), the store and the toast centre.
struct RootView: View {
    @AppStorage(SpaceSetting.key) private var space: SpaceKind = SpaceSetting.defaultValue
    @State private var router = AppRouter(tab: RootView.launchTab)
    @State private var store: AppStore
    @Environment(Session.self) private var session
    private let toasts: ToastCenter
    @State private var showSettings = false
    @State private var showInvite = false

    init(store: AppStore? = nil, toasts: ToastCenter = ToastCenter()) {
        self.toasts = toasts
        // `-noNotifications YES` (launch argument) keeps UI tests and screenshots free of the permission alert.
        let notifier: ReminderNotifying = UserDefaults.standard.bool(forKey: "noNotifications")
            ? NoReminderNotifications()
            : UserNotificationReminders()
        _store = State(initialValue: store ?? AppStore(notifier: notifier))
        // `-initialSpace shared|personal` (launch argument) sets the starting space once and leaves it switchable —
        // unlike `-activeSpace`, which pins the stored value for the whole run.
        if let initial = UserDefaults.standard.string(forKey: "initialSpace"), SpaceKind(rawValue: initial) != nil {
            UserDefaults.standard.set(initial, forKey: SpaceSetting.key)
        }
        // `-alone YES` (launch argument): nobody has joined Shared yet — shows the invite banner.
        if UserDefaults.standard.bool(forKey: "alone") { _store.wrappedValue.partner = nil }
    }

    var body: some View {
        TabView(selection: $router.tab) {
            ForEach(AppTab.allCases) { tab in
                NavigationStack {
                    screen(for: tab)
                        .togetherNavigation(title: title(for: tab), me: store.me, space: $space) {
                            showSettings = true
                        }
                }
                // On the stack, so pushed screens (the note editor) show toasts too.
                .toastHost(enabled: tab != .groceries)
                .tabItem { Label(tab.title, systemImage: tab.icon.systemName) }
                .tag(tab)
            }
        }
        .tint(Accent.of(space).ink)
        .sheet(isPresented: $showSettings) { SettingsView() }
        .sheet(isPresented: $showInvite) { InviteSheet() }
        .onAppear {
            if let name = session.user?.displayName, !name.isEmpty { store.myName = name }
            // A new account arrives alone, with the invite open, or already in someone's Shared space.
            switch session.arrival {
            case .solo?:
                store.leaveShared()
            case .invite?:
                store.leaveShared()
                showInvite = true
            case .joined(let partner)?:
                store.joinPartner(partner)
                toasts.show("You joined \(partner.name)’s Shared space", person: partner)
            case nil:
                break
            }
            session.arrival = nil
        }
        .task {
            // `-demoToast partner|undo` (launch argument) shows a toast on launch — for screenshots of the overlay.
            switch UserDefaults.standard.string(forKey: "demoToast") {
            case "partner": toasts.show("Sam bought Tomatoes", person: .sam)
            case "undo": toasts.showUndo("Tomatoes bought") {}
            default: break
            }
        }
        .environment(\.space, space)
        .environment(\.selectSpace, SelectSpaceAction { [$space] in $space.wrappedValue = $0 })
        .environment(store)
        .environment(router)
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
