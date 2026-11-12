import PhotosUI
import SwiftUI

/// Settings (design/prototype Settings): profile, Shared space, reminders, notifications, appearance, account.
/// Shaped like `/v1/me`, `/v1/me/settings`, `/v1/me/avatar`, `/v1/spaces/{id}/leave`, `DELETE /v1/me`.
struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @Environment(Session.self) private var session
    @Environment(ToastCenter.self) private var toasts
    @Environment(\.dismiss) private var dismiss
    @AppStorage("appearance") private var appearance: Appearance = .system

    @State private var name = ""
    @State private var photo: PhotosPickerItem?
    @State private var pickingPhoto = false
    @State private var showInvite = false
    @State private var confirmLeave = false
    @State private var confirmDelete = false
    @FocusState private var nameFocused: Bool

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            List {
                profile

                Section {
                    if let partner = store.partner {
                        HStack(spacing: TG.Space.s3) {
                            Avatar(person: partner, size: 32)
                            VStack(alignment: .leading, spacing: DS.rowLineGap) {
                                Text(partner.name).font(TG.Font.body).foregroundStyle(TG.Colors.ink)
                                Text("In your Shared space · can see Shared only")
                                    .font(TG.Font.footnote).foregroundStyle(TG.Colors.ink2)
                            }
                        }
                        .accessibilityElement(children: .combine)
                    } else {
                        Button { showInvite = true } label: {
                            HStack(spacing: TG.Space.s3) {
                                Avatar(person: nil, size: 32)
                                Text("Invite your partner").font(TG.Font.body).foregroundStyle(TG.Colors.sharedInk)
                            }
                        }
                    }
                    Toggle(isOn: $store.suggestionsEnabled) {
                        VStack(alignment: .leading, spacing: DS.rowLineGap) {
                            Text("Grocery suggestions").font(TG.Font.body)
                            Text("Based on what you usually buy · never added automatically")
                                .font(TG.Font.footnote).foregroundStyle(TG.Colors.ink2)
                        }
                    }
                    Picker("Shopping day", selection: $store.shoppingDay) {
                        ForEach(1...7, id: \.self) { day in Text(Self.weekdays[day - 1]).tag(day) }
                    }
                } header: {
                    header("Shared space")
                }

                Section {
                    DatePicker("From", selection: quietBinding(\.start), displayedComponents: .hourAndMinute)
                    DatePicker("Until", selection: quietBinding(\.end), displayedComponents: .hourAndMinute)
                } header: {
                    header("Quiet hours")
                } footer: {
                    Text("Reminders that fall inside arrive when quiet hours end.")
                }

                Section {
                    Toggle("Task reminders", isOn: $store.notificationPrefs.taskReminders)
                    Toggle("When someone asks you to do a task", isOn: $store.notificationPrefs.taskAssigned)
                    Toggle("When someone joins your Shared space", isOn: $store.notificationPrefs.partnerJoined)
                    Toggle("Shopping day reminder", isOn: $store.notificationPrefs.groceryReminder)
                } header: {
                    header("Notifications")
                }

                Section {
                    Picker("Appearance", selection: $appearance) {
                        ForEach(Appearance.allCases) { Text($0.title).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .listRowBackground(Color.clear)
                    .listRowInsets(EdgeInsets())
                } header: {
                    header("Appearance")
                }

                Section {
                    if store.partner != nil {
                        Button("Leave Shared space", role: .destructive) { confirmLeave = true }
                    }
                    Button("Log out") { logOut() }
                        .foregroundStyle(TG.Colors.ink)
                    Button("Delete account", role: .destructive) { confirmDelete = true }
                } footer: {
                    Text("Your Personal space is never shared, even if you leave.")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(TG.Colors.bg)
            .font(TG.Font.body)
            .tint(TG.Colors.sharedInk)
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { saveName(); dismiss() }
                }
            }
        }
        .environment(\.space, .shared)
        .onAppear { name = store.myName }
        .onChange(of: photo) { loadPhoto() }
        .sheet(isPresented: $showInvite) { InviteSheet() }
        .confirmSheet(
            isPresented: $confirmLeave,
            title: "Leave the Shared space?",
            message: "You’ll lose the shared groceries, tasks and notes. \(store.partner?.name ?? "Your partner") keeps them. Your Personal space stays as it is.",
            confirm: "Leave Shared space",
            cancel: "Stay",
            icon: .people,
            destructive: true
        ) {
            store.leaveShared()
            toasts.show("You left the Shared space")
        }
        .confirmSheet(
            isPresented: $confirmDelete,
            title: "Delete your account?",
            message: "Your Personal space and everything in it are deleted. This can’t be undone.",
            confirm: "Delete account",
            cancel: "Keep my account",
            icon: .trash,
            destructive: true
        ) {
            Task { try? await session.deleteAccount() }
        }
    }

    // MARK: Pieces

    private var profile: some View {
        Section {
            HStack(spacing: TG.Space.s4) {
                Button { pickingPhoto = true } label: { avatar }
                    .buttonStyle(.bare)
                    .photosPicker(isPresented: $pickingPhoto, selection: $photo, matching: .images)
                    .accessibilityLabel("Change photo")
                VStack(alignment: .leading, spacing: DS.rowLineGap) {
                    TextField("Name", text: $name)
                        .font(TG.Font.headline)
                        .textContentType(.givenName)
                        .submitLabel(.done)
                        .focused($nameFocused)
                        .onSubmit(saveName)
                        .accessibilityLabel("Your name")
                    if let email = session.user?.email {
                        Text(email).font(TG.Font.footnote).foregroundStyle(TG.Colors.ink2)
                    }
                }
            }
            .padding(.vertical, TG.Space.s1)
            .onChange(of: nameFocused) { _, focused in if !focused { saveName() } }
        }
    }

    private var avatar: some View {
        Avatar(person: store.me, size: 56)
    }

    private func header(_ text: String) -> some View {
        Text(text).font(TG.Font.subhead.weight(.semibold)).foregroundStyle(TG.Colors.ink2).textCase(nil)
    }

    private static let weekdays: [String] = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.locale = Locale(identifier: "en_GB")
        return calendar.weekdaySymbols
    }()

    /// Quiet hours are minutes after midnight; the pickers edit them as times of day.
    private func quietBinding(_ keyPath: WritableKeyPath<QuietHours, Int>) -> Binding<Date> {
        Binding(
            get: {
                let minutes = (store.quietHours[store.me] ?? .default)[keyPath: keyPath]
                return Calendar.current.date(bySettingHour: minutes / 60, minute: minutes % 60, second: 0, of: .now) ?? .now
            },
            set: { date in
                let c = Calendar.current.dateComponents([.hour, .minute], from: date)
                var quiet = store.quietHours[store.me] ?? .default
                quiet[keyPath: keyPath] = (c.hour ?? 0) * 60 + (c.minute ?? 0)
                store.quietHours[store.me] = quiet
            }
        )
    }

    // MARK: Actions

    private func saveName() {
        guard let clean = AuthValidation.cleanName(name), clean != store.myName else { return }
        store.myName = clean
        Task { try? await session.rename(to: clean) }
    }

    private func loadPhoto() {
        guard let photo else { return }
        Task {
            if let data = try? await photo.loadTransferable(type: Data.self) { store.myAvatar = data }
        }
    }

    private func logOut() {
        dismiss()
        Task { await session.logout() }
    }
}
