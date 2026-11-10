import Foundation
import Network
import os

/// Keeps `AppStore` and the server in step while signed in against the API.
///
/// - **Load**: `/me`, `/me/settings`, `/spaces`, members, and per space the default list with its items, suggestions,
///   tasks (active + done), notes and three months of trips. The store shows exactly that.
/// - **Changes**: every local change (`record`) is already on screen (optimistic UI). They are sent in order from one
///   queue; an item created here gets the server's ID when its POST returns, and later changes use that ID.
///   Offline, the queue pauses (the banner says so) and resumes when the connection is back; grocery items typed
///   while offline are kept on disk until sent. A change the server refuses is undone, the space is re-fetched and
///   a toast says what happened.
/// - **Realtime**: while the app is in the foreground each space's event stream applies the partner's changes
///   ("Sam bought Tomatoes"); after a reconnect the space is re-fetched (events aren't replayed).
@MainActor
final class RemoteSync: StoreSync {
    let client: APIClient
    private(set) var directory: ServerDirectory
    private weak var store: AppStore?
    private let toasts: ToastCenter
    private let calendar: Calendar

    private var queue: [StoreChange] = []
    private var draining = false
    private var retryTask: Task<Void, Never>?
    private var failures = 0
    /// Client IDs of things created here → the server's IDs.
    private var serverIDs: [UUID: UUID] = [:]
    private var streams: [SpaceKind: SpaceEventStream] = [:]
    private let path = NWPathMonitor()
    private let pending: PendingGroceries
    private static let log = Logger(subsystem: "app.together", category: "sync")

    /// The latest load, for whoever waits on it (the receipt recognizer needs space IDs).
    private(set) var loaded = false
    private var loading = false
    /// The app is in the foreground: streams are open whenever the spaces are known.
    private var foreground = false

    init(client: APIClient, store: AppStore, toasts: ToastCenter, me: Person, calendar: Calendar = .current) {
        self.client = client
        self.store = store
        self.toasts = toasts
        self.calendar = calendar
        directory = ServerDirectory(me: me)
        pending = PendingGroceries(userID: me.id)
        store.sync = self
        path.pathUpdateHandler = { [weak self] path in
            guard path.status == .satisfied else { return }
            Task { @MainActor in self?.connectionCameBack() }
        }
        path.start(queue: .main)
    }

    deinit {
        path.cancel()
    }

    func spaceID(_ kind: SpaceKind) -> UUID? { directory.spaceIDs[kind] }

    /// Changes not yet accepted by the server.
    var pendingCount: Int { queue.count }

    /// Nothing waiting and nothing in flight (tests wait for this).
    var isIdle: Bool { queue.isEmpty && !draining }

    /// The server's ID for something created here.
    func serverID(for localID: UUID) -> UUID { id(localID) }

    // MARK: Load

    /// Everything the app shows, from the server. Called after sign-in, on foreground and after a reconnect.
    /// A load already running is not started twice.
    func loadAll() async {
        guard !loading else { return }
        loading = true
        defer {
            loading = false
            store?.hasLoaded = true // offline too: show what's here (nothing yet) with the banner, not a spinner
            if foreground { openStreams() }
        }
        do {
            let me = try await client.send(.get("v1/me"), as: MeDTO.self)
            let settings = try await client.send(.get("v1/me/settings"), as: SettingsDTO.self)
            let spaces = try await client.send(.get("v1/spaces"), as: SpacesDTO.self).spaces
            var directory = self.directory
            directory.spaceIDs = [:]
            for space in spaces {
                if space.kind == "personal" { directory.spaceIDs[.personal] = space.id }
                if space.kind == "shared" { directory.spaceIDs[.shared] = space.id }
            }
            var partner: Person?
            var myTint: Person.Tint = .alex
            if let shared = directory.spaceIDs[.shared] {
                let members = try await client.send(.get("v1/spaces/\(shared)/members"), as: MembersDTO.self).members
                for person in ServerDirectory.people(from: members) {
                    directory.people[person.id] = person
                    if person.id == me.id { myTint = person.tint } else { partner = person }
                }
            }
            directory.me = Person(id: me.id, name: me.displayName, tint: myTint)
            directory.people[me.id] = directory.me
            self.directory = directory

            var snapshot = Snapshot()
            for (kind, id) in directory.spaceIDs {
                try await snapshot.load(kind, spaceID: id, client: client, directory: &directory, calendar: calendar)
            }
            self.directory = directory
            snapshot.relink(localID)
            apply(me: me, settings: settings, spaces: spaces, partner: partner, snapshot: snapshot)
            loaded = true
            restorePendingGroceries()
            drain()
        } catch APIError.offline {
            store?.connection = .offline(pending: queue.count)
            scheduleRetry()
        } catch APIError.signedOut {
            // The session ends; nothing to show.
        } catch {
            Self.log.error("load failed: \(String(describing: error), privacy: .public)")
            toasts.show("Couldn’t load your lists. Pull to refresh or try again later.")
        }
    }

    /// Re-fetches one space (after a refused change or a stream reconnect).
    func reload(_ kind: SpaceKind) async {
        guard let id = directory.spaceIDs[kind] else { return }
        var snapshot = Snapshot()
        var directory = self.directory
        do {
            try await snapshot.load(kind, spaceID: id, client: client, directory: &directory, calendar: calendar)
        } catch {
            return
        }
        self.directory.defaultListIDs[kind] = directory.defaultListIDs[kind]
        guard let store else { return }
        snapshot.relink(localID)
        store.applyingServer { snapshot.replace(kind, in: store, keepingLocal: localOnlyIDs()) }
    }

    private func apply(me: MeDTO, settings: SettingsDTO, spaces: [SpaceDTO], partner: Person?, snapshot: Snapshot) {
        guard let store else { return }
        store.applyingServer {
            store.me = directory.me
            store.myName = me.displayName
            store.partner = partner
            store.suggestionsEnabled = settings.suggestionsEnabled
            store.notificationPrefs = APIMapping.prefs(settings.notifications)
            var quiet = store.quietHours
            quiet[directory.me] = APIMapping.quietHours(settings.quietHours)
            store.quietHours = quiet
            if let day = spaces.first(where: { $0.kind == "shared" })?.shoppingDay ?? spaces.first?.shoppingDay {
                store.shoppingDay = APIMapping.weekday(apiDay: day) ?? store.shoppingDay
            }
            for kind in SpaceKind.allCases {
                if directory.spaceIDs[kind] == nil {
                    snapshot.clear(kind, in: store)
                } else {
                    snapshot.replace(kind, in: store, keepingLocal: localOnlyIDs())
                }
            }
            store.resyncReminders()
        }
    }

    /// Items created here whose POST hasn't returned: a reload mustn't drop them.
    private func localOnlyIDs() -> Set<UUID> {
        var ids = Set<UUID>()
        for change in queue {
            switch change {
            case .itemAdded(let item, _): ids.insert(item.id)
            case .suggestionsAccepted(_, let added, _): ids.formUnion(added.map(\.id))
            case .taskCreated(let task, _), .taskRestored(let task): ids.insert(task.id)
            case .noteCreated(let note): ids.insert(note.id)
            default: break
            }
        }
        return ids
    }

    // MARK: Changes

    func record(_ change: StoreChange) {
        queue.append(change)
        if case .itemAdded(let item, let space) = change { pending.add(item, space: space) }
        drain()
    }

    private func drain() {
        guard !draining, loaded else { updateConnection(); return }
        draining = true
        Task {
            defer { draining = false; updateConnection() }
            while let change = queue.first {
                do {
                    try await send(change)
                    queue.removeFirst()
                    failures = 0
                    forget(change)
                } catch APIError.offline {
                    store?.connection = .offline(pending: queue.count)
                    scheduleRetry()
                    return
                } catch APIError.signedOut {
                    queue.removeAll()
                    return
                } catch let error as APIError where error.isTransient && failures < 3 {
                    failures += 1
                    try? await Task.sleep(for: .seconds(Double(1 << failures)))
                } catch {
                    queue.removeFirst()
                    failures = 0
                    forget(change)
                    await refused(change, error: error)
                }
            }
        }
    }

    private func updateConnection() {
        guard let store else { return }
        if case .offline = store.connection, !queue.isEmpty {
            store.connection = .offline(pending: queue.count)
        } else if queue.isEmpty, retryTask == nil {
            store.connection = .online
        }
    }

    private func scheduleRetry() {
        guard retryTask == nil else { return }
        retryTask = Task { [weak self] in
            var delay = 2.0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(delay))
                guard let self else { return }
                if await self.probe() { break }
                delay = min(delay * 2, 60)
            }
            self?.retryTask = nil
            self?.resume()
        }
    }

    /// The banner's Retry, or the network coming back.
    func retryNow() {
        retryTask?.cancel()
        retryTask = nil
        resume()
    }

    private func connectionCameBack() {
        guard case .offline? = store?.connection else { return }
        retryNow()
    }

    private func resume() {
        if loaded {
            store?.connection = .online
            drain()
        } else {
            Task { await loadAll() }
        }
    }

    private func probe() async -> Bool {
        do {
            try await client.send(.get("v1/me"))
            return true
        } catch APIError.offline {
            return false
        } catch {
            return true
        }
    }

    private func forget(_ change: StoreChange) {
        if case .itemAdded(let item, _) = change { pending.remove(item.id) }
    }

    private func id(_ local: UUID) -> UUID { serverIDs[local] ?? local }

    /// The server ID of a space. Shared doesn't exist until the first invite — or until something is put in it
    /// while alone; then it is created here (a person has at most one).
    private func space(_ kind: SpaceKind) async throws -> UUID {
        if let id = directory.spaceIDs[kind] { return id }
        guard kind == .shared else {
            throw APIError.server(status: 404, code: "space_not_found", message: "That space isn’t there any more.",
                                  retryAfter: nil, body: Data())
        }
        let spaces = try await client.send(.get("v1/spaces"), as: SpacesDTO.self).spaces
        var found = spaces.first(where: { $0.kind == "shared" })?.id
        if found == nil {
            found = try await client.send(.send("POST", "v1/spaces", json: CreateSpaceBody()), as: SpaceDTO.self).id
        }
        guard let id = found else { throw APIError.badResponse("no Shared space") }
        directory.spaceIDs[.shared] = id
        let list = try await client.send(.get("v1/spaces/\(id)/lists/default"), as: ListWithItemsDTO.self)
        directory.defaultListIDs[.shared] = list.list.id
        if foreground { openStreams() }
        return id
    }

    func spacesChanged() async {
        while loading { try? await Task.sleep(for: .milliseconds(100)) } // a load in flight may predate the change
        await loadAll()
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private func send(_ change: StoreChange) async throws {
        switch change {
        // Groceries
        case .itemAdded(let item, let kind):
            let s = try await space(kind)
            let dto = try await client.send(.send("POST", "v1/spaces/\(s)/lists/default/items",
                                                  json: AddItemBody(name: item.name, qty: item.qty, note: item.note)),
                                            as: GroceryItemDTO.self)
            adopt(dto, replacing: item.id)
        case .itemEdited(let item, let kind):
            let s = try await space(kind)
            let dto = try await client.send(.send("PATCH", "v1/spaces/\(s)/items/\(id(item.id))",
                                                  json: EditItemBody(name: item.name, qty: item.qty ?? "", note: item.note ?? "")),
                                            as: GroceryItemDTO.self)
            adopt(dto, replacing: item.id)
        case .itemBought(let itemID, let kind):
            let s = try await space(kind)
            let dto = try await client.send(.send("POST", "v1/spaces/\(s)/items/\(id(itemID))/bought"), as: GroceryItemDTO.self)
            adopt(dto, replacing: itemID)
        case .itemUnbought(let itemID, let kind):
            let s = try await space(kind)
            let dto = try await client.send(.send("DELETE", "v1/spaces/\(s)/items/\(id(itemID))/bought"), as: GroceryItemDTO.self)
            adopt(dto, replacing: itemID)
        case .itemRemoved(let item, let kind):
            let s = try await space(kind)
            do {
                try await client.send(.delete("v1/spaces/\(s)/items/\(id(item.id))"))
            } catch let error as APIError where error.code == "item_not_found" {
                // Already gone (the partner removed it too).
            }
        case .itemRestored(let item, let kind):
            let s = try await space(kind)
            var dto = try await client.send(.send("POST", "v1/spaces/\(s)/lists/default/items",
                                                  json: AddItemBody(name: item.name, qty: item.qty, note: item.note)),
                                            as: GroceryItemDTO.self)
            if item.done {
                dto = try await client.send(.send("POST", "v1/spaces/\(s)/items/\(dto.id)/bought"), as: GroceryItemDTO.self)
            }
            adopt(dto, replacing: item.id)
        case .suggestionDismissed(let name, let kind):
            let s = try await space(kind)
            try await client.send(.send("POST", "v1/spaces/\(s)/suggestions/dismiss", json: DismissSuggestionBody(name: name)))
        case .suggestionsAccepted(let names, let added, let kind):
            let s = try await space(kind)
            let items = try await client.send(.send("POST", "v1/spaces/\(s)/suggestions/accept",
                                                    json: AcceptSuggestionsBody(names: names)), as: ItemsDTO.self).items
            for dto in items {
                let local = added.first { $0.name.caseInsensitiveCompare(dto.name) == .orderedSame }
                adopt(dto, replacing: local?.id ?? dto.id)
            }
        case .receiptConfirmed(let review, let trip, let kind):
            let s = try await space(kind)
            let body = ConfirmReceiptBody(
                lines: review.lines.filter(\.included).map { line in
                    let matched = line.status == .matched ? line.match : nil
                    return ReceiptLineInBody(
                        name: line.name, qty: line.qty, priceGrosze: APIMapping.grosze(line.price),
                        itemId: matched.flatMap { $0.purchaseID == nil ? id($0.itemID) : nil },
                        purchaseId: matched?.purchaseID
                    )
                },
                totalGrosze: APIMapping.grosze(review.total), merchant: review.merchant, shoppedAt: review.date
            )
            let result = try await client.send(.send("POST", "v1/spaces/\(s)/receipts", json: body), as: ConfirmReceiptDTO.self)
            guard let store else { return }
            store.applyingServer {
                var saved = APIMapping.trip(result.trip, space: kind, directory)
                saved.id = trip.id
                link(trip.id, to: result.trip.id)
                store.trips.removeAll { $0.id == trip.id }
                store.trips.append(saved)
                for dto in result.bought ?? [] { upsert(dto) }
            }

        // Tasks
        case .taskCreated(let task, let draft):
            let s = try await space(task.space)
            let dto = try await client.send(.send("POST", "v1/spaces/\(s)/tasks", json: APIMapping.createBody(task, draft)),
                                            as: TaskDTO.self)
            adopt(dto, replacing: task.id)
        case .taskEdited(let task, _, _):
            let s = try await space(task.space)
            let dto = try await client.send(.send("PATCH", "v1/spaces/\(s)/tasks/\(id(task.id))", json: APIMapping.editBody(task)),
                                            as: TaskDTO.self)
            adopt(dto, replacing: task.id)
        case .taskCompleted(let before):
            let s = try await space(before.space)
            let result = try await client.send(.send("POST", "v1/spaces/\(s)/tasks/\(id(before.id))/complete"),
                                               as: CompleteTaskDTO.self)
            adopt(result.task, replacing: before.id)
        case .taskReopened(let task):
            let s = try await space(task.space)
            let dto = try await client.send(.send("POST", "v1/spaces/\(s)/tasks/\(id(task.id))/reopen"), as: TaskDTO.self)
            adopt(dto, replacing: task.id)
        case .taskDeleted(let task):
            let s = try await space(task.space)
            do {
                try await client.send(.delete("v1/spaces/\(s)/tasks/\(id(task.id))"))
            } catch let error as APIError where error.code == "task_not_found" {}
        case .taskRestored(let task):
            let s = try await space(task.space)
            let draft = AppStore.TaskDraft(title: task.title, notes: task.notes, dueDay: task.dueDay,
                                           repeatRule: task.repeatRule, assignee: task.assignee,
                                           reminderAt: task.reminder?.requested)
            var body = APIMapping.createBody(task, draft)
            if let at = body.reminder?.at, at <= .now { body.reminder = nil } // can't remind in the past
            let dto = try await client.send(.send("POST", "v1/spaces/\(s)/tasks", json: body), as: TaskDTO.self)
            adopt(dto, replacing: task.id)

        // Notes
        case .noteCreated(let note):
            let s = try await space(note.space)
            let dto = try await client.send(.send("POST", "v1/spaces/\(s)/notes",
                                                  json: CreateNoteBody(title: note.title, body: note.body,
                                                                       items: note.checklist.map(\.label))),
                                            as: NoteDTO.self)
            for (local, server) in zip(note.checklist, dto.items.sorted { ($0.position ?? 0) < ($1.position ?? 0) }) {
                serverIDs[local.id] = server.id
            }
            adopt(dto, replacing: note.id)
        case .noteEdited(let note, let base):
            try await saveNote(note, base: base)
        case .noteDeleted(let note):
            let s = try await space(note.space)
            do {
                try await client.send(.delete("v1/spaces/\(s)/notes/\(id(note.id))"))
            } catch let error as APIError where error.code == "note_not_found" {}
        case .noteRestored(let note):
            let s = try await space(note.space)
            let dto = try await client.send(.send("POST", "v1/spaces/\(s)/notes/\(id(note.id))/restore"), as: NoteDTO.self)
            adopt(dto, replacing: note.id)
        case .noteMoved(let note, let from):
            let s = try await space(from)
            let target = try await space(note.space)
            let result = try await client.send(.send("POST", "v1/spaces/\(s)/notes/\(id(note.id))/move",
                                                     json: MoveNoteBody(spaceId: target)), as: MoveNoteDTO.self)
            adopt(result.note, replacing: note.id)
        case .checklistAdded(let item, let noteID, let at, let kind):
            let s = try await space(kind)
            let dto = try await client.send(.send("POST", "v1/spaces/\(s)/notes/\(id(noteID))/items",
                                                  json: AddNoteItemBody(text: item.label, position: at)), as: NoteDTO.self)
            // The new line is the one at `at` that we don't know yet.
            let known = Set(serverIDs.values)
            if let server = dto.items.first(where: { $0.position == at && !known.contains($0.id) })
                ?? dto.items.first(where: { !known.contains($0.id) && $0.text == item.label }) {
                serverIDs[item.id] = server.id
            }
            adoptChecklist(dto, noteID: noteID)
        case .checklistEdited(let itemID, let noteID, let text, let done, let position, let kind):
            let s = try await space(kind)
            let dto = try await client.send(.send("PATCH", "v1/spaces/\(s)/notes/\(id(noteID))/items/\(id(itemID))",
                                                  json: EditNoteItemBody(text: text, done: done, position: position)),
                                            as: NoteDTO.self)
            adoptChecklist(dto, noteID: noteID)
        case .checklistDeleted(let itemID, let noteID, let kind):
            let s = try await space(kind)
            do {
                let dto = try await client.send(.delete("v1/spaces/\(s)/notes/\(id(noteID))/items/\(id(itemID))"), as: NoteDTO.self)
                adoptChecklist(dto, noteID: noteID)
            } catch let error as APIError where error.code == "item_not_found" {}

        // Me, settings, membership
        case .settingsChanged:
            guard let store else { return }
            try await client.send(.send("PATCH", "v1/me/settings",
                                        json: SettingsPatchBody(suggestionsEnabled: store.suggestionsEnabled,
                                                                notifications: APIMapping.prefsDTO(store.notificationPrefs))))
            await reloadSuggestions()
        case .shoppingDayChanged(let weekday):
            for kind in SpaceKind.allCases {
                guard let s = directory.spaceIDs[kind] else { continue }
                try await client.send(.send("PATCH", "v1/spaces/\(s)",
                                            json: SpacePatchBody(shoppingDay: APIMapping.apiDay(weekday: weekday))))
            }
        case .quietHoursChanged(let quiet):
            try await client.send(.send("PATCH", "v1/me/settings",
                                        json: SettingsPatchBody(quietHours: APIMapping.quietHoursDTO(quiet))))
        case .avatarChanged(let data):
            if let data {
                var request = APIRequest(method: "PUT", path: "v1/me/avatar", body: data,
                                         contentType: data.starts(with: [0x89, 0x50]) ? "image/png" : "image/jpeg")
                request.timeout = 60
                try await client.send(request)
            } else {
                try await client.send(.delete("v1/me/avatar"))
            }
        case .leftShared:
            guard let s = directory.spaceIDs[.shared] else { return }
            try await client.send(.send("POST", "v1/spaces/\(s)/leave"))
            directory.spaceIDs[.shared] = nil
            directory.defaultListIDs[.shared] = nil
            streams[.shared]?.stop()
            streams[.shared] = nil
        }
    }

    /// PATCH with `If-Match`. On `409 version_conflict` the partner saved in between: take theirs where I didn't
    /// change a field, mine where I did, and save once more; the editor is told to reload and says it merged.
    private func saveNote(_ note: Note, base: Note) async throws {
        let s = try await space(note.space)
        var request = APIRequest.send("PATCH", "v1/spaces/\(s)/notes/\(id(note.id))",
                                      json: EditNoteBody(title: note.title, body: note.body))
        request.headers["If-Match"] = "\"\(base.version)\""
        do {
            let dto = try await client.send(request, as: NoteDTO.self)
            adopt(dto, replacing: note.id)
        } catch let error as APIError where error.code == "version_conflict" {
            guard case .server(_, _, _, _, let body) = error,
                  let theirs = try? APICoding.decoder.decode(NoteConflictDTO.self, from: body).note else { throw error }
            let title = note.title != base.title ? note.title : theirs.title
            let text = note.body != base.body ? note.body : theirs.body
            var retry = APIRequest.send("PATCH", "v1/spaces/\(s)/notes/\(id(note.id))", json: EditNoteBody(title: title, body: text))
            retry.headers["If-Match"] = "\"\(theirs.version)\""
            let dto = try await client.send(retry, as: NoteDTO.self)
            adopt(dto, replacing: note.id)
            store?.noteMerges[note.id, default: 0] += 1
        }
    }

    private func reloadSuggestions() async {
        for (kind, s) in directory.spaceIDs {
            guard let list = try? await client.send(.get("v1/spaces/\(s)/suggestions"), as: SuggestionsDTO.self) else { continue }
            store?.applyingServer { store?.suggestionsBySpace[kind] = list.suggestions.map(APIMapping.suggestion) }
        }
    }

    /// The server said no (not a connection problem): undo what the screen shows, re-fetch, explain.
    private func refused(_ change: StoreChange, error: Error) async {
        guard let store else { return }
        let message = (error as? APIError)?.message ?? "Something went wrong."
        Self.log.error("change refused: \(String(describing: error), privacy: .public)")
        var kind: SpaceKind?
        store.applyingServer {
            switch change {
            case .itemAdded(let item, let space):
                store.groceryItems.removeAll { $0.id == item.id }
                kind = space
                toasts.show("Couldn’t add \(item.name). \(message)")
            case .itemBought(let itemID, let space):
                if let i = store.groceryItems.firstIndex(where: { $0.id == itemID }) {
                    store.groceryItems[i].done = false
                    store.groceryItems[i].boughtBy = nil
                    store.groceryItems[i].boughtAt = nil
                }
                kind = space
                toasts.show("Couldn’t mark it bought. \(message)")
            case .taskCompleted(let before):
                if let i = store.tasks.firstIndex(where: { $0.id == before.id }) { store.tasks[i] = before }
                store.syncNotification(before)
                kind = before.space
                toasts.show("Couldn’t complete “\(before.title)”. \(message)")
            case .itemEdited(_, let space), .itemUnbought(_, let space), .itemRemoved(_, let space),
                 .itemRestored(_, let space), .suggestionDismissed(_, let space), .suggestionsAccepted(_, _, let space),
                 .receiptConfirmed(_, _, let space), .checklistAdded(_, _, _, let space),
                 .checklistEdited(_, _, _, _, _, let space), .checklistDeleted(_, _, let space):
                kind = space
                toasts.show(message)
            case .taskCreated(let task, _), .taskEdited(let task, _, _), .taskReopened(let task), .taskDeleted(let task),
                 .taskRestored(let task):
                kind = task.space
                toasts.show(message)
            case .noteCreated(let note), .noteEdited(let note, _), .noteDeleted(let note), .noteRestored(let note):
                kind = note.space
                toasts.show(message)
            case .noteMoved(let note, let from):
                kind = from
                toasts.show(message)
                Task { await self.reload(note.space) }
            case .settingsChanged, .shoppingDayChanged, .quietHoursChanged, .avatarChanged, .leftShared:
                toasts.show(message)
            }
        }
        if let kind { await reload(kind) } else { await loadAll() }
    }

    func loadLines(of tripID: Trip.ID) async {
        guard let store, let trip = store.trips.first(where: { $0.id == tripID }), let s = directory.spaceIDs[trip.space],
              let dto = try? await client.send(.get("v1/spaces/\(s)/trips/\(id(tripID))"), as: TripDTO.self) else { return }
        store.applyingServer {
            guard let i = store.trips.firstIndex(where: { $0.id == tripID }) else { return }
            var full = APIMapping.trip(dto, space: trip.space, directory)
            full.id = tripID
            store.trips[i] = full
        }
    }

    // MARK: Server state into the store

    /// Puts the server's version of something created or changed here in place of the local one.
    /// Server IDs stay out of the store: what was created here keeps its local ID (open sheets, Undo and focus
    /// hold it), and `serverIDs` translates.
    private func link(_ localID: UUID, to serverID: UUID) {
        guard localID != serverID else { return }
        serverIDs[localID] = serverID
    }

    /// The store's ID for something the server sent.
    private func localID(_ serverID: UUID) -> UUID {
        serverIDs.first { $0.value == serverID }?.key ?? serverID
    }

    private func adopt(_ dto: GroceryItemDTO, replacing localID: UUID) {
        link(localID, to: dto.id)
        guard let store else { return }
        store.applyingServer {
            var item = APIMapping.item(dto, directory)
            item.id = self.localID(dto.id)
            let copies = store.groceryItems.indices.filter { store.groceryItems[$0].id == item.id }
            if let first = copies.first {
                store.groceryItems[first] = item
                for extra in copies.dropFirst().reversed() { store.groceryItems.remove(at: extra) }
            } else {
                store.groceryItems.insert(item, at: 0)
            }
        }
    }

    private func adopt(_ dto: TaskDTO, replacing localID: UUID) {
        link(localID, to: dto.id)
        guard let store, let kind = directory.kind(of: dto.spaceId) else { return }
        store.applyingServer {
            var task = APIMapping.task(dto, space: kind, directory)
            task.id = self.localID(dto.id)
            if let i = store.tasks.firstIndex(where: { $0.id == task.id }) {
                var merged = task
                merged.previousDueDay = store.tasks[i].previousDueDay // the server keeps its own for reopen
                store.tasks[i] = merged
            } else {
                store.tasks.insert(task, at: 0)
            }
            store.syncNotification(task)
        }
    }

    private func adopt(_ dto: NoteDTO, replacing localID: UUID) {
        link(localID, to: dto.id)
        guard let store, let kind = directory.kind(of: dto.spaceId) else { return }
        store.applyingServer {
            var note = APIMapping.note(dto, space: kind, directory)
            note.id = self.localID(dto.id)
            if let i = store.notes.firstIndex(where: { $0.id == note.id }) {
                // Keep the local IDs the editor is focused on; the server IDs are in `serverIDs`.
                note.checklist = mergeChecklist(local: store.notes[i].checklist, server: note.checklist)
                store.notes[i] = note
            } else {
                store.notes.append(note)
            }
        }
    }

    /// A checklist answer replaces the lines, but the lines added here keep their local IDs (focus, row state).
    private func adoptChecklist(_ dto: NoteDTO, noteID: UUID) {
        guard let store, let kind = directory.kind(of: dto.spaceId),
              let i = store.notes.firstIndex(where: { $0.id == noteID }) else { return }
        store.applyingServer {
            let server = APIMapping.note(dto, space: kind, directory)
            store.notes[i].checklist = mergeChecklist(local: store.notes[i].checklist, server: server.checklist)
            store.notes[i].version = server.version
            store.notes[i].updatedAt = server.updatedAt
            store.notes[i].updatedBy = server.updatedBy
        }
    }

    private func mergeChecklist(local: [ChecklistItem], server: [ChecklistItem]) -> [ChecklistItem] {
        let localByServerID = Dictionary(local.map { (id($0.id), $0) }, uniquingKeysWith: { a, _ in a })
        var merged = server.map { item -> ChecklistItem in
            guard let mine = localByServerID[item.id] else { return item }
            var kept = item
            kept.id = mine.id
            return kept
        }
        // Lines still on their way to the server stay where they are.
        let sent = Set(merged.map(\.id))
        for (offset, item) in local.enumerated() where !sent.contains(item.id) && serverIDs[item.id] == nil {
            merged.insert(item, at: min(offset, merged.count))
        }
        return merged
    }

    private func upsert(_ dto: GroceryItemDTO) {
        guard let store else { return }
        var item = APIMapping.item(dto, directory)
        item.id = localID(dto.id)
        if let i = store.groceryItems.firstIndex(where: { $0.id == item.id }) {
            store.groceryItems[i] = item
        } else {
            store.groceryItems.insert(item, at: 0)
        }
    }

    // MARK: Offline grocery adds

    /// Items typed while offline that never reached the server (the app was closed): back on the list and in the
    /// queue.
    private func restorePendingGroceries() {
        guard let store else { return }
        let waiting = pending.all().filter { saved in !queue.contains { change in
            if case .itemAdded(let item, _) = change { return item.id == saved.item.id }
            return false
        } }
        guard !waiting.isEmpty else { return }
        store.applyingServer {
            for saved in waiting where !store.groceryItems.contains(where: { $0.id == saved.item.id }) {
                var item = saved.item
                if let list = directory.defaultListIDs[saved.space] { item.listID = list }
                store.groceryItems.insert(item, at: 0)
            }
        }
        for saved in waiting {
            var item = saved.item
            if let list = directory.defaultListIDs[saved.space] { item.listID = list }
            queue.append(.itemAdded(item, saved.space))
        }
    }

    // MARK: Realtime

    /// Foreground: one stream per space. Background: none (the server limits open streams). Before the first load
    /// the spaces aren't known yet; the streams open when it finishes.
    func setForeground(_ foreground: Bool) {
        self.foreground = foreground
        if foreground {
            openStreams()
        } else {
            for stream in streams.values { stream.stop() }
            streams = [:]
        }
    }

    private func openStreams() {
        for (kind, id) in directory.spaceIDs where streams[kind] == nil {
            let stream = SpaceEventStream(client: client, spaceID: id) { [weak self] event in
                self?.apply(event, in: kind)
            } reconnected: { [weak self] in
                await self?.reload(kind)
            }
            streams[kind] = stream
            stream.start()
        }
    }

    func stop() {
        setForeground(false)
        retryTask?.cancel()
        path.cancel()
        if store?.sync === self { store?.sync = nil }
    }

    /// One event from the partner (my own come back too; their effect is already here).
    func apply(_ event: SpaceEventDTO, in kind: SpaceKind) {
        guard let store, event.actorId != directory.me.id else { return }
        let actor = directory.person(event.actorId)
        store.applyingServer {
            switch event.type {
            case "item.added", "item.updated", "item.bought", "item.unbought":
                guard let dto = event.item else { return }
                upsert(dto)
                if event.type == "item.bought", let actor { toasts.show("\(actor.name) bought \(dto.name)", person: actor) }
            case "item.removed":
                if let removed = event.removedId { store.groceryItems.removeAll { $0.id == localID(removed) } }
            case "trip.created":
                guard let dto = event.trip else { return }
                var trip = APIMapping.trip(dto, space: kind, directory)
                trip.id = localID(dto.id)
                store.trips.removeAll { $0.id == trip.id }
                store.trips.append(trip)
            case "task.created", "task.updated", "task.completed", "task.reopened":
                guard let dto = event.task else { return }
                var task = APIMapping.task(dto, space: kind, directory)
                task.id = localID(dto.id)
                if let i = store.tasks.firstIndex(where: { $0.id == task.id }) {
                    store.tasks[i] = task
                } else {
                    store.tasks.insert(task, at: 0)
                }
                store.syncNotification(task)
                if event.type == "task.completed", let actor { toasts.show("\(actor.name) did “\(dto.title)”", person: actor) }
            case "task.deleted":
                if let removed = event.removedId {
                    store.tasks.removeAll { $0.id == localID(removed) }
                    store.notifier.cancel(id: localID(removed).uuidString)
                }
            case "note.created", "note.updated", "note.restored", "note.moved_in":
                guard let dto = event.note else { return }
                var note = APIMapping.note(dto, space: kind, directory)
                note.id = localID(dto.id)
                if let i = store.notes.firstIndex(where: { $0.id == note.id }) {
                    var updated = note
                    updated.checklist = mergeChecklist(local: store.notes[i].checklist, server: note.checklist)
                    store.notes[i] = updated
                } else {
                    store.notes.append(note)
                }
            case "note.deleted", "note.moved_out":
                if let removed = event.removedId ?? event.note?.id { store.notes.removeAll { $0.id == localID(removed) } }
            case "space.member_joined":
                guard let member = event.member else { return }
                let person = Person(id: member.userId, name: member.displayName, tint: .sam)
                directory.people[person.id] = person
                store.partner = person
                toasts.show("\(person.name) joined your Shared space", person: person)
            case "list.created", "list.updated", "list.deleted":
                Task { await self.reload(kind) }
            default:
                break
            }
        }
    }
}

/// One fetch of a space, applied in one go.
private struct Snapshot {
    var lists: [SpaceKind: [GroceryList]] = [:]
    var items: [SpaceKind: [GroceryItem]] = [:]
    var suggestions: [SpaceKind: [Suggestion]] = [:]
    var tasks: [SpaceKind: [TaskItem]] = [:]
    var notes: [SpaceKind: [Note]] = [:]
    var trips: [SpaceKind: [Trip]] = [:]

    mutating func load(_ kind: SpaceKind, spaceID: UUID, client: APIClient, directory: inout ServerDirectory,
                       calendar: Calendar) async throws {
        let s = spaceID
        let list = try await client.send(.get("v1/spaces/\(s)/lists/default"), as: ListWithItemsDTO.self)
        directory.defaultListIDs[kind] = list.list.id
        let dir = directory
        lists[kind] = [APIMapping.list(list.list, space: kind)]
        items[kind] = list.items.map { APIMapping.item($0, dir) }
        suggestions[kind] = try await client.send(.get("v1/spaces/\(s)/suggestions"), as: SuggestionsDTO.self)
            .suggestions.map(APIMapping.suggestion)
        let active = try await client.send(.get("v1/spaces/\(s)/tasks", query: [URLQueryItem(name: "view", value: "active")]),
                                           as: TasksDTO.self).tasks
        let done = try await client.send(.get("v1/spaces/\(s)/tasks", query: [URLQueryItem(name: "view", value: "done")]),
                                         as: TasksDTO.self).tasks
        tasks[kind] = (active + done).map { APIMapping.task($0, space: kind, dir) }
        notes[kind] = try await client.send(.get("v1/spaces/\(s)/notes"), as: NotesDTO.self)
            .notes.map { APIMapping.note($0, space: kind, dir) }
        // History: this month and the two before.
        var collected: [Trip] = []
        let zone = calendar.timeZone.identifier
        for back in 0..<3 {
            guard let date = calendar.date(byAdding: .month, value: -back, to: .now) else { continue }
            let c = calendar.dateComponents([.year, .month], from: date)
            let month = String(format: "%04d-%02d", c.year!, c.month!)
            let page = try await client.send(.get("v1/spaces/\(s)/trips", query: [
                URLQueryItem(name: "month", value: month), URLQueryItem(name: "tz", value: zone),
            ]), as: TripsPageDTO.self)
            // Without lines: a trip's lines are fetched when it is opened (`RemoteSync.loadLines`).
            for trip in page.trips where !collected.contains(where: { $0.id == trip.id }) {
                collected.append(APIMapping.trip(trip, space: kind, dir))
            }
        }
        trips[kind] = collected
    }

    /// Things created on this phone keep their local IDs in the store.
    mutating func relink(_ localID: (UUID) -> UUID) {
        for kind in items.keys { items[kind] = items[kind]?.map { var x = $0; x.id = localID(x.id); return x } }
        for kind in tasks.keys { tasks[kind] = tasks[kind]?.map { var x = $0; x.id = localID(x.id); return x } }
        for kind in notes.keys { notes[kind] = notes[kind]?.map { var x = $0; x.id = localID(x.id); return x } }
        for kind in trips.keys { trips[kind] = trips[kind]?.map { var x = $0; x.id = localID(x.id); return x } }
    }

    @MainActor
    func replace(_ kind: SpaceKind, in store: AppStore, keepingLocal localIDs: Set<UUID>) {
        let oldListIDs = Set(store.lists.filter { $0.space == kind }.map(\.id))
        if let items = items[kind] {
            // Items still on their way to the server stay, on the server's default list.
            let pendingLocal = store.groceryItems.filter { localIDs.contains($0.id) && oldListIDs.contains($0.listID) }
            store.groceryItems.removeAll { oldListIDs.contains($0.listID) }
            let defaultList = lists[kind]?.first(where: \.isDefault)?.id
            store.groceryItems.append(contentsOf: pendingLocal.map { item in
                var item = item
                if let defaultList { item.listID = defaultList }
                return item
            } + items)
        }
        if let lists = lists[kind] {
            store.lists.removeAll { $0.space == kind }
            store.lists.append(contentsOf: lists)
        }
        if let suggestions = suggestions[kind] { store.suggestionsBySpace[kind] = suggestions }
        if let tasks = tasks[kind] {
            let pendingLocal = store.tasks.filter { $0.space == kind && localIDs.contains($0.id) }
            store.tasks.removeAll { $0.space == kind }
            store.tasks.append(contentsOf: pendingLocal + tasks)
        }
        if let notes = notes[kind] {
            let pendingLocal = store.notes.filter { $0.space == kind && localIDs.contains($0.id) }
            store.notes.removeAll { $0.space == kind }
            store.notes.append(contentsOf: pendingLocal + notes)
        }
        if let trips = trips[kind] {
            store.trips.removeAll { $0.space == kind }
            store.trips.append(contentsOf: trips)
        }
    }

    @MainActor
    func clear(_ kind: SpaceKind, in store: AppStore) {
        let listIDs = Set(store.lists.filter { $0.space == kind }.map(\.id))
        store.groceryItems.removeAll { listIDs.contains($0.listID) }
        store.tasks.removeAll { $0.space == kind }
        store.notes.removeAll { $0.space == kind }
        store.trips.removeAll { $0.space == kind }
        store.suggestionsBySpace[kind] = []
    }
}

/// Grocery items typed but not yet accepted by the server, on disk per user, so closing the app offline loses
/// nothing.
final class PendingGroceries {
    struct Saved: Codable {
        var item: GroceryItem
        var space: SpaceKind
    }

    private let url: URL

    init(userID: UUID) {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        url = folder.appending(path: "pending-groceries-\(userID.uuidString).json")
    }

    func all() -> [Saved] {
        guard let data = try? Data(contentsOf: url) else { return [] }
        return (try? JSONDecoder().decode([Saved].self, from: data)) ?? []
    }

    func add(_ item: GroceryItem, space: SpaceKind) {
        var saved = all()
        saved.removeAll { $0.item.id == item.id }
        saved.append(Saved(item: item, space: space))
        write(saved)
    }

    func remove(_ id: UUID) {
        var saved = all()
        saved.removeAll { $0.item.id == id }
        write(saved)
    }

    private func write(_ saved: [Saved]) {
        if saved.isEmpty {
            try? FileManager.default.removeItem(at: url)
        } else if let data = try? JSONEncoder().encode(saved) {
            try? data.write(to: url, options: [.atomic, .completeFileProtection])
        }
    }
}
