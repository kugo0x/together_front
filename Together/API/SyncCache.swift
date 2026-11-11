import Foundation

/// One space's data as the server sent it: what a load fetches and what the cache keeps.
struct SpaceFetch: Codable, Sendable {
    var list: ListWithItemsDTO
    var suggestions: [SuggestionDTO]
    var tasks: [TaskDTO]
    var notes: [NoteDTO]
    /// This month and the two before, without lines (a trip's lines are fetched when it is opened).
    var trips: [TripDTO]

    /// All of it at once — the requests run in parallel.
    static func fetch(spaceID s: UUID, client: APIClient, calendar: Calendar) async throws -> SpaceFetch {
        async let list = client.send(.get("v1/spaces/\(s)/lists/default"), as: ListWithItemsDTO.self)
        async let suggestions = client.send(.get("v1/spaces/\(s)/suggestions"), as: SuggestionsDTO.self)
        async let active = client.send(.get("v1/spaces/\(s)/tasks", query: [URLQueryItem(name: "view", value: "active")]),
                                       as: TasksDTO.self)
        async let done = client.send(.get("v1/spaces/\(s)/tasks", query: [URLQueryItem(name: "view", value: "done")]),
                                     as: TasksDTO.self)
        async let notes = client.send(.get("v1/spaces/\(s)/notes"), as: NotesDTO.self)
        async let trips = recentTrips(spaceID: s, client: client, calendar: calendar)
        return try await SpaceFetch(list: list, suggestions: suggestions.suggestions, tasks: active.tasks + done.tasks,
                                    notes: notes.notes, trips: trips)
    }

    private static func recentTrips(spaceID: UUID, client: APIClient, calendar: Calendar) async throws -> [TripDTO] {
        let zone = calendar.timeZone.identifier
        let months: [String] = (0..<3).compactMap { back in
            guard let date = calendar.date(byAdding: .month, value: -back, to: .now) else { return nil }
            let c = calendar.dateComponents([.year, .month], from: date)
            return String(format: "%04d-%02d", c.year!, c.month!)
        }
        return try await withThrowingTaskGroup(of: (Int, [TripDTO]).self) { group in
            for (index, month) in months.enumerated() {
                group.addTask {
                    let page = try await client.send(.get("v1/spaces/\(spaceID)/trips", query: [
                        URLQueryItem(name: "month", value: month), URLQueryItem(name: "tz", value: zone),
                    ]), as: TripsPageDTO.self)
                    return (index, page.trips)
                }
            }
            var pages = [[TripDTO]](repeating: [], count: months.count)
            for try await (index, trips) in group { pages[index] = trips }
            var seen = Set<UUID>()
            return pages.joined().filter { seen.insert($0.id).inserted }
        }
    }
}

/// A whole load: who I am, my settings, my spaces, the Shared space's members and every space's data.
struct SyncBundle: Codable, Sendable {
    var me: MeDTO
    var settings: SettingsDTO
    var spaces: [SpaceDTO]
    var members: [MemberDTO]
    var spaceData: [SpaceKind: SpaceFetch]

    static func spaceIDs(_ spaces: [SpaceDTO]) -> [SpaceKind: UUID] {
        var ids: [SpaceKind: UUID] = [:]
        for space in spaces {
            if space.kind == "personal" { ids[.personal] = space.id }
            if space.kind == "shared" { ids[.shared] = space.id }
        }
        return ids
    }
}

/// The last load on disk, per user, so the next launch shows it at once while the fresh one loads.
/// Removed at sign-out. A file from an older app version that no longer decodes is just ignored.
struct SyncCache {
    private struct Stored: Codable {
        var version: Int
        var bundle: SyncBundle
    }

    private static let version = 1
    private let url: URL

    init(userID: UUID) {
        url = Self.url(for: userID)
    }

    func read() -> SyncBundle? {
        guard let data = try? Data(contentsOf: url),
              let stored = try? JSONDecoder().decode(Stored.self, from: data),
              stored.version == Self.version else { return nil }
        return stored.bundle
    }

    func write(_ bundle: SyncBundle) {
        guard let data = try? JSONEncoder().encode(Stored(version: Self.version, bundle: bundle)) else { return }
        try? data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    static func remove(userID: UUID) {
        try? FileManager.default.removeItem(at: url(for: userID))
    }

    private static func url(for userID: UUID) -> URL {
        let folder = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appending(path: "sync-cache-\(userID.uuidString).json")
    }
}
