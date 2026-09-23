import Foundation

/// What somebody is allowed to do in a group.
///
/// Ranks only ever go up. There is deliberately no way to demote anyone: once you have
/// made somebody a co-host they are a co-host for good, which is the whole point of the
/// permission being permanent. The one thing that moves rather than accumulates is the
/// host title, and only the host themselves can move it.
enum GroupRole: String, Codable, Sendable, CaseIterable, Comparable {
    case member
    case coHost
    case host

    private var rank: Int {
        switch self {
        case .member: 0
        case .coHost: 1
        case .host: 2
        }
    }

    static func < (lhs: GroupRole, rhs: GroupRole) -> Bool { lhs.rank < rhs.rank }

    var label: String {
        switch self {
        case .member: "Member"
        case .coHost: "Co-host"
        case .host: "Host"
        }
    }

    var symbolName: String {
        switch self {
        case .member: "person.fill"
        case .coHost: "checkmark.seal.fill"
        case .host: "crown.fill"
        }
    }

    /// Co-hosts can bring people up to co-host and change the code. Only the host can
    /// hand the host title on.
    var canPromoteToCoHost: Bool { self >= .coHost }
    var canChangeCode: Bool { self >= .coHost }
    var canHandOverHost: Bool { self == .host }
}

/// Enough about a pet to list it as a member on a phone that has never met it.
struct GroupMemberInfo: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    var kind: PetKind
    var appearance: PetAppearance

    init(id: String, name: String, kind: PetKind, appearance: PetAppearance) {
        self.id = id
        self.name = name
        self.kind = kind
        self.appearance = appearance
    }

    init(pet: Pet) {
        self.init(id: pet.id.uuidString, name: pet.name, kind: pet.kind, appearance: pet.appearance)
    }

    // Decoded defensively: this arrives from another phone, possibly a different build.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? ""
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Someone's pet"
        kind = try container.decodeIfPresent(PetKind.self, forKey: .kind) ?? .cat
        appearance = try container.decodeIfPresent(PetAppearance.self, forKey: .appearance) ?? PetAppearance()
    }
}

/// One thing that happened in a group.
///
/// A group holds no state of its own. Everything about it — who is in it, who runs it,
/// what the code is — is worked out by replaying these in order. The log only ever grows,
/// and every phone sorts it identically, so two phones that have each seen a different
/// half of what happened agree completely the moment they meet. There is no server to
/// ask, and none is needed.
struct GroupEvent: Codable, Sendable, Identifiable, Equatable {
    enum Kind: String, Codable, Sendable {
        case created
        case joined
        /// Co-host, granted for good.
        case promoted
        /// The host title moving from one pet to another.
        case handedHost
        case codeChanged
        /// Something a newer build knows about and this one doesn't. Ignored when
        /// replaying, but carried along so it isn't lost on the way through.
        case unknown

        init(from decoder: any Decoder) throws {
            let raw = try decoder.singleValueContainer().decode(String.self)
            self = Kind(rawValue: raw) ?? .unknown
        }
    }

    var id: String
    var kind: Kind
    var date: Date
    /// Who did it.
    var actorID: String
    /// Who it was done to. The same as `actorID` for `created` and `joined`.
    var subjectID: String
    /// The subject's pet, so they can be listed by a phone that has never met them.
    var subject: GroupMemberInfo?
    /// The group's name on `created`, and the new code on `codeChanged`.
    var text: String?

    init(
        kind: Kind,
        actorID: String,
        subjectID: String,
        subject: GroupMemberInfo? = nil,
        text: String? = nil,
        date: Date = .now
    ) {
        self.id = UUID().uuidString
        self.kind = kind
        self.date = date
        self.actorID = actorID
        self.subjectID = subjectID
        self.subject = subject
        self.text = text
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        kind = try container.decodeIfPresent(Kind.self, forKey: .kind) ?? .unknown
        date = try container.decodeIfPresent(Date.self, forKey: .date) ?? .now
        actorID = try container.decodeIfPresent(String.self, forKey: .actorID) ?? ""
        subjectID = try container.decodeIfPresent(String.self, forKey: .subjectID) ?? ""
        subject = try? container.decodeIfPresent(GroupMemberInfo.self, forKey: .subject)
        text = try container.decodeIfPresent(String.self, forKey: .text)
    }
}

/// A friend group: a name, a code to get in, and the log of everything that has happened
/// to it.
struct PetGroup: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var events: [GroupEvent]

    init(id: String = UUID().uuidString, events: [GroupEvent]) {
        self.id = id
        self.events = events
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        events = try container.decodeIfPresent([GroupEvent].self, forKey: .events) ?? []
    }

    /// Starts a group off, with its founder as the host and a fresh code.
    static func founded(by pet: Pet, named name: String) -> PetGroup {
        let founder = GroupMemberInfo(pet: pet)
        let now = Date.now
        return PetGroup(events: [
            GroupEvent(kind: .created, actorID: founder.id, subjectID: founder.id,
                       subject: founder, text: name, date: now),
            GroupEvent(kind: .codeChanged, actorID: founder.id, subjectID: founder.id,
                       text: InviteCode.make(), date: now)
        ])
    }
}

// MARK: - Replay

extension PetGroup {
    /// The log in the one order every phone agrees on. Ties on the clock are broken by
    /// event id, which is arbitrary but identical everywhere.
    var ordered: [GroupEvent] {
        events
            .filter { $0.kind != .unknown }
            .sorted { ($0.date, $0.id) < ($1.date, $1.id) }
    }

    private var creation: GroupEvent? {
        ordered.first { $0.kind == .created }
    }

    var name: String {
        let name = creation?.text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return name.isEmpty ? "Group" : name
    }

    var founderID: String? { creation?.actorID }

    /// Who runs it now. The most recent handover wins, and since every phone sorts the
    /// handovers the same way, no two phones can disagree about who that is — even if
    /// they saw them in a different order, or one of them missed a few.
    var hostID: String? {
        ordered.last { $0.kind == .handedHost }?.subjectID ?? founderID
    }

    var inviteCode: String {
        ordered.last { $0.kind == .codeChanged }?.text ?? ""
    }

    /// Everyone ever trusted with more than plain membership. Grow-only — nothing comes
    /// back out of this set, which is what makes the permission permanent.
    var coHostIDs: Set<String> {
        var ids: Set<String> = []
        if let founderID { ids.insert(founderID) }
        for event in ordered {
            switch event.kind {
            case .promoted:
                ids.insert(event.subjectID)
            case .handedHost:
                // Both ends of a handover keep co-host: the new host for obvious
                // reasons, and the old one because what they had can't be taken off
                // them either.
                ids.insert(event.subjectID)
                ids.insert(event.actorID)
            default:
                break
            }
        }
        return ids
    }

    /// Members in the order they joined, with the freshest details for each — a pet that
    /// has been renamed or recoloured since shows up as it is now.
    var members: [GroupMemberInfo] {
        var latest: [String: GroupMemberInfo] = [:]
        var order: [String] = []
        for event in ordered where event.kind == .created || event.kind == .joined {
            guard let subject = event.subject, !subject.id.isEmpty else { continue }
            if latest[subject.id] == nil { order.append(subject.id) }
            latest[subject.id] = subject
        }
        return order.compactMap { latest[$0] }
    }

    var memberIDs: Set<String> { Set(members.map(\.id)) }

    func contains(_ id: String) -> Bool { memberIDs.contains(id) }

    /// Nil for somebody who isn't in the group at all.
    func role(of id: String) -> GroupRole? {
        guard contains(id) else { return nil }
        if id == hostID { return .host }
        if coHostIDs.contains(id) { return .coHost }
        return .member
    }

    /// Members sorted for display: host, then co-hosts, then everyone else by join order.
    var rankedMembers: [GroupMemberInfo] {
        members.enumerated()
            .sorted { left, right in
                let leftRole = role(of: left.element.id) ?? .member
                let rightRole = role(of: right.element.id) ?? .member
                if leftRole != rightRole { return leftRole > rightRole }
                return left.offset < right.offset
            }
            .map(\.element)
    }

    /// Two copies of the same group, combined. A union of the logs is all a grow-only
    /// log ever needs — there is nothing to reconcile, because nothing was ever removed.
    func merging(_ other: PetGroup) -> PetGroup {
        guard other.id == id else { return self }
        var byID: [String: GroupEvent] = [:]
        for event in events + other.events {
            byID[event.id] = event
        }
        return PetGroup(id: id, events: Array(byID.values))
    }

    /// Adds an event, unless an identical one is already in the log.
    func appending(_ event: GroupEvent) -> PetGroup {
        guard !events.contains(where: { $0.id == event.id }) else { return self }
        return PetGroup(id: id, events: events + [event])
    }
}

// MARK: - Invite codes

/// Codes are read out loud across a room and typed in by somebody else, so the alphabet
/// leaves out every character anyone has ever mistaken for another one: no O or 0, no
/// I or 1.
enum InviteCode {
    static let length = 6
    private static let alphabet = Array("ABCDEFGHJKLMNPQRSTUVWXYZ23456789")

    static func make() -> String {
        String((0..<length).compactMap { _ in alphabet.randomElement() })
    }

    /// Takes whatever somebody typed and makes a code of it: case, spaces and dashes are
    /// all forgiven, and anything that isn't in the alphabet is dropped.
    static func normalised(_ text: String) -> String {
        let usable = text.uppercased().filter { alphabet.contains($0) }
        return String(usable.prefix(length))
    }

    static func isComplete(_ text: String) -> Bool {
        normalised(text).count == length
    }
}

// MARK: - Storage

/// Groups on disk. Tiny — a group is a handful of events — so the whole lot is one file.
enum GroupArchive {
    private static let fileName = "groups.json"

    /// A group somebody left is remembered by id, so that the next phone to sync it back
    /// doesn't quietly put them in it again.
    private struct Stored: Codable {
        var groups: [PetGroup] = []
        var forgotten: [String] = []

        init(groups: [PetGroup], forgotten: [String]) {
            self.groups = groups
            self.forgotten = forgotten
        }

        init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            groups = try container.decodeIfPresent([PetGroup].self, forKey: .groups) ?? []
            forgotten = try container.decodeIfPresent([String].self, forKey: .forgotten) ?? []
        }
    }

    private static var fileURL: URL? {
        let shared = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PetArchive.appGroupIdentifier)
        let base = shared ?? (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ))
        guard let base else { return nil }
        let folder = base.appendingPathComponent("PetPhone", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    static func load() -> (groups: [PetGroup], forgotten: Set<String>) {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return ([], []) }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let stored = try? decoder.decode(Stored.self, from: data) else { return ([], []) }
        return (stored.groups, Set(stored.forgotten))
    }

    static func save(_ groups: [PetGroup], forgotten: Set<String>) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let stored = Stored(groups: groups, forgotten: Array(forgotten))
        guard let data = try? encoder.encode(stored) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func erase() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}
