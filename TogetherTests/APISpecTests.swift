import Foundation
import Testing
@testable import Together

/// The client's wire models against the backend's contract (`TogetherTests/Resources/openapi.json`, a copy of
/// back/api/openapi.yaml made by `scripts/update-openapi.sh`).
///
/// - Every response schema the app reads gets an example built from the spec (its `example`s, else a value of the
///   right type and format; once with every nullable field filled, once with them all `null`), and that must decode.
/// - Every request body the app sends may only use properties the spec declares (the API rejects unknown fields)
///   and must include the required ones.
struct APISpecTests {
    nonisolated(unsafe) static let spec: [String: Any] = {
        let url = Bundle(for: BundleToken.self).url(forResource: "openapi", withExtension: "json")!
        return try! JSONSerialization.jsonObject(with: Data(contentsOf: url)) as! [String: Any]
    }()

    final class BundleToken {}

    static var schemas: [String: Any] {
        ((spec["components"] as! [String: Any])["schemas"] as! [String: Any])
    }

    // MARK: Responses

    /// Response schema → the type that reads it.
    nonisolated(unsafe) static let responses: [(String, (Data) throws -> Void)] = [
        ("Me", { _ = try APICoding.decoder.decode(MeDTO.self, from: $0) }),
        ("User", { _ = try APICoding.decoder.decode(UserDTO.self, from: $0) }),
        ("Tokens", { _ = try APICoding.decoder.decode(TokensDTO.self, from: $0) }),
        ("AuthResult", { _ = try APICoding.decoder.decode(AuthResultDTO.self, from: $0) }),
        ("MySpace", { _ = try APICoding.decoder.decode(SpaceDTO.self, from: $0) }),
        ("Space", { _ = try APICoding.decoder.decode(SpaceDTO.self, from: $0) }),
        ("Member", { _ = try APICoding.decoder.decode(MemberDTO.self, from: $0) }),
        ("Invite", { _ = try APICoding.decoder.decode(InviteDTO.self, from: $0) }),
        ("InvitePreview", { _ = try APICoding.decoder.decode(InvitePreviewDTO.self, from: $0) }),
        ("GroceryList", { _ = try APICoding.decoder.decode(GroceryListDTO.self, from: $0) }),
        ("GroceryItem", { _ = try APICoding.decoder.decode(GroceryItemDTO.self, from: $0) }),
        ("Purchase", { _ = try APICoding.decoder.decode(PurchaseDTO.self, from: $0) }),
        ("Trip", { _ = try APICoding.decoder.decode(TripDTO.self, from: $0) }),
        ("MonthSummary", { _ = try APICoding.decoder.decode(MonthSummaryDTO.self, from: $0) }),
        ("Suggestion", { _ = try APICoding.decoder.decode(SuggestionDTO.self, from: $0) }),
        ("Task", { _ = try APICoding.decoder.decode(TaskDTO.self, from: $0) }),
        ("Reminder", { _ = try APICoding.decoder.decode(ReminderDTO.self, from: $0) }),
        ("Device", { _ = try APICoding.decoder.decode(DeviceDTO.self, from: $0) }),
        ("Note", { _ = try APICoding.decoder.decode(NoteDTO.self, from: $0) }),
        ("NoteItem", { _ = try APICoding.decoder.decode(NoteItemDTO.self, from: $0) }),
        ("Home", { _ = try APICoding.decoder.decode(HomeDTO.self, from: $0) }),
        ("Settings", { _ = try APICoding.decoder.decode(SettingsDTO.self, from: $0) }),
        ("ReceiptScan", { _ = try APIReceiptRecognizer.decode($0) }),
        ("GroceryEvent", { _ = try APICoding.decoder.decode(SpaceEventDTO.self, from: $0) }),
        ("TaskEvent", { _ = try APICoding.decoder.decode(SpaceEventDTO.self, from: $0) }),
        ("NoteEvent", { _ = try APICoding.decoder.decode(SpaceEventDTO.self, from: $0) }),
    ]

    @Test(arguments: responses.map(\.0))
    func responseSchemaDecodes(_ name: String) throws {
        let decode = try #require(Self.responses.first { $0.0 == name }?.1)
        for nulls in [false, true] {
            var synth = Synthesizer(nullsWhereAllowed: nulls)
            let example = try synth.example(for: ["$ref": "#/components/schemas/\(name)"])
            let data = try JSONSerialization.data(withJSONObject: example)
            do {
                try decode(data)
            } catch {
                Issue.record("\(name) (nulls: \(nulls)) doesn't decode: \(error)\n\(String(decoding: data, as: UTF8.self))")
            }
        }
    }

    /// The member-joined event isn't `required`-typed in the spec; build it by hand from its properties.
    @Test func memberJoinedEventDecodes() throws {
        var synth = Synthesizer(nullsWhereAllowed: false, fillOptional: true)
        let example = try synth.example(for: ["$ref": "#/components/schemas/MemberJoinedEvent"])
        _ = try APICoding.decoder.decode(SpaceEventDTO.self, from: JSONSerialization.data(withJSONObject: example))
    }

    /// Wrapped list answers (`{"lists": [...]}`, …) and the trips page.
    @Test func pathResponsesDecode() throws {
        func body(_ path: String, _ method: String, status: String = "200") throws -> Data {
            let paths = Self.spec["paths"] as! [String: Any]
            let op = (paths[path] as! [String: Any])[method] as! [String: Any]
            let response = (op["responses"] as! [String: Any])[status] as! [String: Any]
            let schema = ((response["content"] as! [String: Any])["application/json"] as! [String: Any])["schema"]!
            var synth = Synthesizer(nullsWhereAllowed: false, fillOptional: true)
            return try JSONSerialization.data(withJSONObject: synth.example(for: schema))
        }
        _ = try APICoding.decoder.decode(SpacesDTO.self, from: body("/v1/spaces", "get"))
        _ = try APICoding.decoder.decode(MembersDTO.self, from: body("/v1/spaces/{spaceID}/members", "get"))
        _ = try APICoding.decoder.decode(ListsDTO.self, from: body("/v1/spaces/{spaceID}/lists", "get"))
        _ = try APICoding.decoder.decode(ListWithItemsDTO.self, from: body("/v1/spaces/{spaceID}/lists/{listID}", "get"))
        _ = try APICoding.decoder.decode(ItemsDTO.self, from: body("/v1/spaces/{spaceID}/suggestions/accept", "post", status: "201"))
        _ = try APICoding.decoder.decode(TripsPageDTO.self, from: body("/v1/spaces/{spaceID}/trips", "get"))
        _ = try APICoding.decoder.decode(SuggestionsDTO.self, from: body("/v1/spaces/{spaceID}/suggestions", "get"))
        _ = try APICoding.decoder.decode(TasksDTO.self, from: body("/v1/spaces/{spaceID}/tasks", "get"))
        _ = try APICoding.decoder.decode(CompleteTaskDTO.self, from: body("/v1/spaces/{spaceID}/tasks/{taskID}/complete", "post"))
        _ = try APICoding.decoder.decode(NotesDTO.self, from: body("/v1/spaces/{spaceID}/notes", "get"))
        _ = try APICoding.decoder.decode(MoveNoteDTO.self, from: body("/v1/spaces/{spaceID}/notes/{noteID}/move", "post"))
        _ = try APICoding.decoder.decode(DeleteNoteDTO.self, from: body("/v1/spaces/{spaceID}/notes/{noteID}", "delete"))
        _ = try APICoding.decoder.decode(ConfirmReceiptDTO.self, from: body("/v1/spaces/{spaceID}/receipts", "post", status: "201"))
        _ = try APICoding.decoder.decode(AcceptInviteDTO.self, from: body("/v1/invites/{code}/accept", "post"))
    }

    // MARK: Requests

    /// (method path, what the app sends).
    nonisolated(unsafe) static let requests: [(String, any Encodable)] = [
        ("post /v1/auth/register", RegisterBody(email: "a@b.co", password: "12345678", displayName: "Alex")),
        ("post /v1/auth/login", LoginBody(email: "a@b.co", password: "12345678")),
        ("post /v1/auth/apple", IDTokenBody(idToken: "t", nonce: "n", displayName: "Alex")),
        ("post /v1/auth/google", IDTokenBody(idToken: "t", nonce: "n")),
        ("post /v1/auth/refresh", RefreshBody(refreshToken: "r")),
        ("post /v1/auth/password/forgot", EmailBody(email: "a@b.co")),
        ("patch /v1/me", MePatchBody(displayName: "Alex", timeZone: "Europe/Warsaw", quietHours: QuietHoursDTO(start: "22:00", end: "08:00"))),
        ("patch /v1/me/settings", SettingsPatchBody(timeZone: "Europe/Warsaw", quietHours: QuietHoursDTO(start: "22:00", end: "08:00"),
                                                    suggestionsEnabled: true,
                                                    notifications: NotificationsDTO(taskReminders: true, taskAssigned: true,
                                                                                    partnerJoined: true, groceryReminder: false))),
        ("post /v1/me/devices", DeviceBody(token: "ab", environment: "sandbox")),
        ("post /v1/spaces", CreateSpaceBody()),
        ("patch /v1/spaces/{spaceID}", SpacePatchBody(shoppingDay: 6)),
        ("post /v1/spaces/{spaceID}/lists/{listID}/items", AddItemBody(text: "2 oat milk", name: "Oat milk", qty: "2", note: "n")),
        ("patch /v1/spaces/{spaceID}/items/{itemID}", EditItemBody(name: "Oat milk", qty: "", note: "")),
        ("post /v1/spaces/{spaceID}/suggestions/dismiss", DismissSuggestionBody(name: "Eggs")),
        ("post /v1/spaces/{spaceID}/suggestions/accept", AcceptSuggestionsBody(names: ["Eggs"])),
        ("post /v1/spaces/{spaceID}/receipts", ConfirmReceiptBody(
            lines: [ReceiptLineInBody(name: "OAT MILK", qty: "2", priceGrosze: 998, itemId: UUID(), purchaseId: UUID())],
            totalGrosze: 998, merchant: "Biedronka", shoppedAt: .now)),
        ("post /v1/spaces/{spaceID}/tasks", CreateTaskBody(title: "T", notes: "n", due: DueDTO(date: "2026-11-09"), repeat: "weekly",
                                                           assigneeId: UUID(), reminder: ReminderInBody(at: .now))),
        ("patch /v1/spaces/{spaceID}/tasks/{taskID}", EditTaskBody(title: "T", notes: nil, due: nil, repeat: nil, assigneeId: nil,
                                                                   sendsAssignee: true, reminder: nil)),
        ("post /v1/spaces/{spaceID}/notes", CreateNoteBody(title: "T", body: "B", items: ["x"])),
        ("patch /v1/spaces/{spaceID}/notes/{noteID}", EditNoteBody(title: "T", body: "B")),
        ("post /v1/spaces/{spaceID}/notes/{noteID}/move", MoveNoteBody(spaceId: UUID())),
        ("post /v1/spaces/{spaceID}/notes/{noteID}/items", AddNoteItemBody(text: "x", position: 0)),
        ("patch /v1/spaces/{spaceID}/notes/{noteID}/items/{itemID}", EditNoteItemBody(text: "x", done: true, position: 1)),
    ]

    @Test(arguments: requests.map(\.0))
    func requestBodyMatchesTheSpec(_ route: String) throws {
        let body = try #require(Self.requests.first { $0.0 == route }?.1)
        let parts = route.split(separator: " ")
        let paths = Self.spec["paths"] as! [String: Any]
        let op = try #require((paths[String(parts[1])] as? [String: Any])?[String(parts[0])] as? [String: Any], "\(route) not in the spec")
        var schema = try #require(Self.requestSchema(op), "\(route) has no JSON body in the spec")
        schema = Synthesizer.resolve(schema)
        let sent = try #require(JSONSerialization.jsonObject(with: APICoding.encoder.encode(AnyEncodable(body))) as? [String: Any])
        try Self.check(sent, against: schema, at: route)
    }

    @Test func receiptLinesUseKnownFields() throws {
        let line = try #require(JSONSerialization.jsonObject(with: APICoding.encoder.encode(
            ReceiptLineInBody(name: "A", qty: "1", priceGrosze: 1, itemId: UUID(), purchaseId: UUID()))) as? [String: Any])
        try Self.check(line, against: Synthesizer.resolve(["$ref": "#/components/schemas/ReceiptLineIn"]), at: "ReceiptLineIn")
    }

    // MARK: Helpers

    static func requestSchema(_ op: [String: Any]) -> Any? {
        var body = op["requestBody"] as? [String: Any]
        if let ref = body?["$ref"] as? String {
            let name = ref.components(separatedBy: "/").last!
            body = ((spec["components"] as! [String: Any])["requestBodies"] as! [String: Any])[name] as? [String: Any]
        }
        return ((body?["content"] as? [String: Any])?["application/json"] as? [String: Any])?["schema"]
    }

    static func check(_ sent: [String: Any], against schema: Any, at route: String) throws {
        let object = Synthesizer.resolve(schema) as? [String: Any] ?? [:]
        let properties = Synthesizer.properties(of: object)
        for key in sent.keys {
            #expect(properties[key] != nil, "\(route): `\(key)` isn't in the spec (the API rejects unknown fields)")
        }
        for key in Synthesizer.required(of: object) {
            #expect(sent[key] != nil, "\(route): required `\(key)` not sent")
        }
        for (key, value) in sent {
            guard let nested = value as? [String: Any], let schema = properties[key] else { continue }
            let resolved = Synthesizer.resolve(schema)
            if (resolved as? [String: Any])?["properties"] != nil || (resolved as? [String: Any])?["allOf"] != nil {
                try check(nested, against: resolved, at: "\(route).\(key)")
            }
        }
        for (key, value) in sent {
            guard let array = value as? [[String: Any]], let items = (Synthesizer.resolve(properties[key] ?? [:]) as? [String: Any])?["items"]
            else { continue }
            for element in array { try check(element, against: items, at: "\(route).\(key)[]") }
        }
    }
}

private struct AnyEncodable: Encodable {
    let value: any Encodable
    init(_ value: any Encodable) { self.value = value }
    func encode(to encoder: Encoder) throws { try value.encode(to: encoder) }
}

/// Builds an example value for a JSON schema of the spec.
struct Synthesizer {
    /// Nullable fields get `null` (else a value).
    var nullsWhereAllowed: Bool
    /// Optional (non-required) properties are filled too.
    var fillOptional = true
    private var depth = 0

    init(nullsWhereAllowed: Bool, fillOptional: Bool = true) {
        self.nullsWhereAllowed = nullsWhereAllowed
        self.fillOptional = fillOptional
    }

    static func resolve(_ schema: Any) -> Any {
        guard let object = schema as? [String: Any] else { return schema }
        if let ref = object["$ref"] as? String {
            let name = ref.components(separatedBy: "/").last!
            return resolve(APISpecTests.schemas[name]!)
        }
        return object
    }

    static func properties(of object: [String: Any]) -> [String: Any] {
        var all = object["properties"] as? [String: Any] ?? [:]
        for part in object["allOf"] as? [Any] ?? [] {
            if let resolved = resolve(part) as? [String: Any] {
                all.merge(properties(of: resolved)) { a, _ in a }
            }
        }
        return all
    }

    static func required(of object: [String: Any]) -> [String] {
        var all = object["required"] as? [String] ?? []
        for part in object["allOf"] as? [Any] ?? [] {
            if let resolved = resolve(part) as? [String: Any] { all += required(of: resolved) }
        }
        return all
    }

    mutating func example(for schema: Any) throws -> Any {
        depth += 1
        defer { depth -= 1 }
        guard depth < 20 else { return NSNull() }
        let object = Self.resolve(schema) as? [String: Any] ?? [:]

        if let variants = object["oneOf"] as? [Any] {
            let nonNull = variants.filter { (Self.resolve($0) as? [String: Any])?["type"] as? String != "null" }
            let nullable = nonNull.count < variants.count
            if nullable && nullsWhereAllowed { return NSNull() }
            return try example(for: nonNull.first ?? [:])
        }
        if object["allOf"] != nil || object["properties"] != nil {
            var result: [String: Any] = [:]
            let required = Set(Self.required(of: object))
            for (key, property) in Self.properties(of: object) where fillOptional || required.contains(key) {
                result[key] = try example(for: property)
            }
            if Self.types(object).contains("null"), nullsWhereAllowed { return NSNull() }
            return result
        }
        if let constant = object["const"] { return constant }
        let types = Self.types(object)
        if types.contains("null"), nullsWhereAllowed { return NSNull() }
        if let options = object["enum"] as? [Any], let first = options.first(where: { !($0 is NSNull) }) { return first }
        if let example = object["example"], !(example is NSNull) {
            // `format: date-time` examples aren't given in the spec; others are fine as written.
            return example
        }
        switch types.first(where: { $0 != "null" }) {
        case "string":
            switch object["format"] as? String {
            case "uuid": return UUID().uuidString.lowercased()
            case "date-time": return "2026-11-09T14:37:00Z"
            case "date": return "2026-11-09"
            case "email": return "alex@example.com"
            case "uri": return "https://together.app/invite/TGT-7KQ2"
            case "binary": return ""
            default: return "text"
            }
        case "integer": return 3
        case "number": return 0.456
        case "boolean": return true
        case "array":
            return [try example(for: object["items"] ?? ["type": "string"])]
        case "object": return [String: Any]()
        default: return "text"
        }
    }

    static func types(_ object: [String: Any]) -> [String] {
        if let type = object["type"] as? String { return [type] }
        if let types = object["type"] as? [Any] { return types.map { ($0 as? String) ?? "null" } }
        return []
    }
}
