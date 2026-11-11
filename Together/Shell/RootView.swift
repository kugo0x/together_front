import SwiftUI

/// The app shell: four tabs, each a large-title navigation stack with the avatar (→ Settings) leading and
/// the space switcher trailing. Owns the global space (persisted), the store and the toast centre.
struct RootView: View {
    @AppStorage(SpaceSetting.key) private var space: SpaceKind = SpaceSetting.defaultValue
    @State private var router = AppRouter(tab: RootView.launchTab)
    @State private var store: AppStore
    @Environment(Session.self) private var session
    @Environment(\.backend) private var backend
    @Environment(\.scenePhase) private var scenePhase
    /// Signed in against the API: keeps the store and the server in step.
    @State private var sync: RemoteSync?
    @State private var wasInBackground = false
    private let toasts: ToastCenter
    @State private var showSettings = false
    @State private var showInvite = false

    init(store: AppStore? = nil, toasts: ToastCenter = ToastCenter()) {
        self.toasts = toasts
        // `-noNotifications YES` (launch argument) keeps UI tests and screenshots free of the permission alert.
        let notifier: ReminderNotifying = UserDefaults.standard.bool(forKey: "noNotifications")
            ? NoReminderNotifications()
            : UserNotificationReminders()
        // On the API the store starts empty and `RemoteSync` fills it; on fakes it starts with the mock data.
        _store = State(initialValue: store ?? AppStore(data: APIConfig.usesFakes ? .make() : .empty, notifier: notifier))
        if store == nil, !APIConfig.usesFakes { _store.wrappedValue.hasLoaded = false }
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
        .overlay {
            if !store.hasLoaded {
                ZStack {
                    TG.Colors.bg.ignoresSafeArea()
                    ProgressView("Loading your spaces…")
                        .font(TG.Font.subhead)
                        .foregroundStyle(TG.Colors.ink2)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.2), value: store.hasLoaded)
        .safeAreaInset(edge: .top, spacing: 0) {
            if case .offline(let pending) = store.connection {
                OfflineBanner(pending: pending) { sync?.retryNow() }
            }
        }
        .animation(.easeInOut(duration: 0.2), value: store.connection)
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
        .task { await startSync() }
        .onChange(of: scenePhase) { _, phase in
            guard let sync else { return }
            // Only a real trip to the background closes the streams and re-fetches on return; pulling down
            // Control Center or the notification shade (inactive) keeps everything as it is.
            switch phase {
            case .background:
                wasInBackground = true
                sync.setForeground(false)
            case .active:
                sync.setForeground(true)
                if wasInBackground {
                    wasInBackground = false
                    Task { await sync.loadAll() }
                }
            default:
                break
            }
        }
        .onDisappear { sync?.stop() }
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
        .environment(\.receiptRecognizer, receiptRecognizer)
        .environment(\.receiptTestInput, Self.receiptTestInput)
        .environment(toasts)
    }

    /// Signed in against the API: load everything, open the event streams, register for push.
    private func startSync() async {
        guard let backend, sync == nil, let user = session.user else { return }
        let me = Person(id: user.id, name: user.displayName, tint: .alex)
        let sync = RemoteSync(client: backend.client, store: store, toasts: toasts, me: me, calendar: store.calendar)
        self.sync = sync
        store.applyingServer {
            store.me = me
            store.partner = nil
        }
        // The view appears in the foreground (`scenePhase` read here can still say "inactive" during launch).
        sync.setForeground(true)
        await sync.loadAll()
        backend.push.start(client: backend.client)
        if let fresh = try? await backend.auth.me() { session.refreshUser(fresh) }
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

    /// Receipt reading. Until phase 9 wires `APIReceiptRecognizer`, a stand-in answers like the backend would.
    /// Launch arguments (UI tests and screenshots):
    /// - `-receiptFixture <name>` picks its answer (`ReceiptFixture.all`: corner, biedronka, mismatch, offline,
    ///   unreadable, notReceipt, tooLong, busy, limit, disabled); `corner,biedronka` answers each
    ///   receipt of a queue with the next one;
    /// - `-receiptDelay <ms>` how long "reading" takes (default 2500).
    private var receiptRecognizer: ReceiptRecognizer {
        if let backend {
            let sync = sync
            return backend.receiptRecognizer { sync?.spaceID($0) }
        }
        let defaults = UserDefaults.standard
        let names = (defaults.string(forKey: "receiptFixture") ?? "corner").split(separator: ",").map(String.init)
        let delay = defaults.object(forKey: "receiptDelay") != nil ? defaults.integer(forKey: "receiptDelay") : 2500
        let store = store
        return FakeReceiptRecognizer(
            fixtures: names.compactMap { ReceiptFixture.all[$0] },
            delay: .milliseconds(delay),
            candidates: { store.receiptCandidates(in: $0) },
            calendar: store.calendar
        )
    }

    /// `-receiptPhotos N` opens the scan sheet with N blank photos instead of the camera (N > 1 asks how they go
    /// together); `-receiptSeparate YES|NO` answers that question.
    private static var receiptTestInput: ReceiptTestInput? {
        let defaults = UserDefaults.standard
        let count = defaults.integer(forKey: "receiptPhotos")
        guard count > 0 else { return nil }
        let separate = defaults.object(forKey: "receiptSeparate") != nil ? defaults.bool(forKey: "receiptSeparate") : nil
        return .photos(count, separate: separate)
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
