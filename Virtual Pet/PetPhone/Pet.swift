import Foundation

/// Tuning knobs for the whole simulation, gathered in one place so the pet can be made
/// more or less demanding without hunting through the code.
enum PetRules {
    // Idle drift, expressed per hour of wall-clock time.
    static let fullnessDecayPerHour = 0.075
    static let funDecayPerHour = 0.090
    static let affectionDecayPerHour = 0.130
    static let restRecoveryPerHour = 0.220

    // Live interaction, expressed per second of contact.
    static let affectionPerSecondOfPetting = 0.0130
    static let restCostPerSecondOfPetting = 0.0040
    static let affectionPerSecondHeld = 0.0016
    static let funPerSecondHeld = 0.0006
    static let restRecoveryPerSecondAsleep = 0.00022

    // Discrete care actions.
    static let fullnessPerMeal = 0.34
    static let funPerPlaySession = 0.30
    static let restCostPerPlaySession = 0.13
    static let fullnessCostPerPlaySession = 0.05

    /// Needs only catch up over three days, so coming back after a holiday finds a sulky
    /// pet rather than a dead one. Nothing in this app ever dies.
    static let maximumCatchUp: TimeInterval = 60 * 60 * 72

    /// How long the phone must lie still before the pet notices it has been abandoned.
    static let setDownGracePeriod: TimeInterval = 40
    /// Minimum gap between "you put me down" complaints, so it nags but isn't unbearable.
    static let complaintCooldown: TimeInterval = 150
}

/// The four things a pet wants. Everything is normalised 0...1, where 1 is fully satisfied.
struct Needs: Codable, Sendable, Equatable {
    var fullness: Double = 0.82
    var fun: Double = 0.74
    var affection: Double = 0.68
    var rest: Double = 0.95

    mutating func clamp() {
        fullness = min(max(fullness, 0), 1)
        fun = min(max(fun, 0), 1)
        affection = min(max(affection, 0), 1)
        rest = min(max(rest, 0), 1)
    }

    func value(for kind: NeedKind) -> Double {
        switch kind {
        case .fullness: fullness
        case .fun: fun
        case .affection: affection
        case .rest: rest
        }
    }
}

enum NeedKind: String, CaseIterable, Identifiable, Sendable {
    case affection
    case fun
    case fullness
    case rest

    var id: String { rawValue }

    var label: String {
        switch self {
        case .affection: "Affection"
        case .fun: "Fun"
        case .fullness: "Food"
        case .rest: "Rest"
        }
    }

    var symbolName: String {
        switch self {
        case .affection: "heart.fill"
        case .fun: "tennisball.fill"
        case .fullness: "fork.knife"
        case .rest: "moon.zzz.fill"
        }
    }
}

enum Mood: String, Sendable {
    case ecstatic
    case happy
    case content
    case restless
    case sad
    case miserable

    var label: String {
        switch self {
        case .ecstatic: "Over the moon"
        case .happy: "Happy"
        case .content: "Content"
        case .restless: "Restless"
        case .sad: "Sad"
        case .miserable: "Miserable"
        }
    }

    var emoji: String {
        switch self {
        case .ecstatic: "✨"
        case .happy: "😊"
        case .content: "🙂"
        case .restless: "😕"
        case .sad: "🥺"
        case .miserable: "😿"
        }
    }
}

/// Another pet this pet has met in the wild.
struct FriendRecord: Codable, Identifiable, Sendable, Equatable {
    var id: String
    var name: String
    var kind: PetKind
    var meetings: Int
    var lastMetAt: Date
    var bond: Double

    var bondTitle: String {
        switch bond {
        case ..<0.2: "Sniffing distance"
        case ..<0.45: "Acquaintance"
        case ..<0.7: "Playmate"
        case ..<0.9: "Best friend"
        default: "Inseparable"
        }
    }
}

/// Everything the app remembers about a pet between launches.
struct Pet: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var kind: PetKind
    var bornAt: Date
    /// Last time the person did something caring: petting, feeding, playing or holding.
    var lastTendedAt: Date
    /// Last moment the simulation ran, so needs can catch up after the app was closed.
    var lastSimulatedAt: Date
    var needs: Needs
    var bondPoints: Double
    var friends: [FriendRecord]
    /// Where the pet considers home. Set from the first location fix, changeable in settings.
    var homeLatitude: Double?
    var homeLongitude: Double?

    init(name: String, kind: PetKind, now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.bornAt = now
        self.lastTendedAt = now
        self.lastSimulatedAt = now
        self.needs = Needs()
        self.bondPoints = 0
        self.friends = []
    }

    // Decoded defensively: a save file written by an older build is missing keys added
    // later, and a pet should survive an app update.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Friend"
        kind = try container.decodeIfPresent(PetKind.self, forKey: .kind) ?? .cat
        bornAt = try container.decodeIfPresent(Date.self, forKey: .bornAt) ?? .now
        lastTendedAt = try container.decodeIfPresent(Date.self, forKey: .lastTendedAt) ?? .now
        lastSimulatedAt = try container.decodeIfPresent(Date.self, forKey: .lastSimulatedAt) ?? .now
        needs = try container.decodeIfPresent(Needs.self, forKey: .needs) ?? Needs()
        bondPoints = try container.decodeIfPresent(Double.self, forKey: .bondPoints) ?? 0
        friends = try container.decodeIfPresent([FriendRecord].self, forKey: .friends) ?? []
        homeLatitude = try container.decodeIfPresent(Double.self, forKey: .homeLatitude)
        homeLongitude = try container.decodeIfPresent(Double.self, forKey: .homeLongitude)
    }
}

extension Pet {
    var voice: VoiceProfile { kind.voice }
    var palette: PetPalette { kind.palette }

    /// Weighted blend of the needs. Affection counts most: this pet is about contact.
    var moodScore: Double {
        let blend = 0.36 * needs.affection
            + 0.28 * needs.fun
            + 0.24 * needs.fullness
            + 0.12 * needs.rest
        // A single badly neglected need drags the whole mood down.
        let worst = min(needs.affection, min(needs.fun, min(needs.fullness, needs.rest)))
        let penalty = worst < 0.2 ? (0.2 - worst) * 1.5 : 0
        return min(max(blend - penalty, 0), 1)
    }

    var mood: Mood {
        switch moodScore {
        case 0.86...: .ecstatic
        case 0.66..<0.86: .happy
        case 0.46..<0.66: .content
        case 0.28..<0.46: .restless
        case 0.12..<0.28: .sad
        default: .miserable
        }
    }

    /// The need that most wants attention, or `nil` when everything is comfortable.
    var neediest: NeedKind? {
        let ranked = NeedKind.allCases.min { needs.value(for: $0) < needs.value(for: $1) }
        guard let ranked, needs.value(for: ranked) < 0.55 else { return nil }
        return ranked
    }

    var level: Int { Int((bondPoints / 45).squareRoot()) + 1 }

    var progressToNextLevel: Double {
        let current = Double((level - 1) * (level - 1)) * 45
        let next = Double(level * level) * 45
        guard next > current else { return 0 }
        return min(max((bondPoints - current) / (next - current), 0), 1)
    }

    var levelTitle: String {
        switch level {
        case 1: "Brand new"
        case 2: "Settling in"
        case 3: "Attached"
        case 4: "Devoted"
        case 5: "Bonded"
        case 6...8: "Soulmate"
        default: "Legendary companion"
        }
    }

    var ageDescription: String {
        let days = Int(Date.now.timeIntervalSince(bornAt) / 86_400)
        return switch days {
        case 0: "Adopted today"
        case 1: "1 day old"
        default: "\(days) days old"
        }
    }

    var timeSinceTended: TimeInterval { Date.now.timeIntervalSince(lastTendedAt) }

    /// Advances idle drift up to `date`. Safe to call repeatedly; it only moves forward.
    mutating func advance(to date: Date) {
        let elapsed = min(max(date.timeIntervalSince(lastSimulatedAt), 0), PetRules.maximumCatchUp)
        lastSimulatedAt = date
        guard elapsed > 0.5 else { return }

        let hours = elapsed / 3600
        needs.fullness -= PetRules.fullnessDecayPerHour * hours
        needs.fun -= PetRules.funDecayPerHour * hours
        needs.affection -= PetRules.affectionDecayPerHour * hours
        needs.rest += PetRules.restRecoveryPerHour * hours
        needs.clamp()
    }

    mutating func recordCare(bond: Double, now: Date = .now) {
        lastTendedAt = now
        bondPoints += bond
    }

    mutating func remember(friend card: PetCard, now: Date = .now) {
        if let index = friends.firstIndex(where: { $0.id == card.id }) {
            friends[index].meetings += 1
            friends[index].lastMetAt = now
            friends[index].name = card.name
            friends[index].kind = card.kind
            friends[index].bond = min(friends[index].bond + 0.12, 1)
        } else {
            friends.append(
                FriendRecord(id: card.id, name: card.name, kind: card.kind,
                             meetings: 1, lastMetAt: now, bond: 0.12)
            )
        }
        friends.sort { $0.lastMetAt > $1.lastMetAt }
    }
}

/// Simple JSON-on-disk storage. A pet is a few hundred bytes; no database required.
enum PetArchive {
    private static let fileName = "pet.json"

    private static var fileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        let folder = base.appendingPathComponent("PetPhone", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder.appendingPathComponent(fileName)
    }

    static func load() -> Pet? {
        guard let fileURL, let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Pet.self, from: data)
    }

    static func save(_ pet: Pet) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(pet) else { return }
        try? data.write(to: fileURL, options: .atomic)
    }

    static func erase() {
        guard let fileURL else { return }
        try? FileManager.default.removeItem(at: fileURL)
    }
}

/// User-facing toggles, small enough to live in `UserDefaults`.
struct Preferences: Codable, Sendable, Equatable {
    var soundEnabled = true
    var hapticsEnabled = true
    /// When true the pet can be heard even with the ringer switch flipped to silent.
    var overridesSilentSwitch = true
    var notificationsEnabled = true
    var nearbyEnabled = true

    private static let key = "PetPhone.preferences"

    static func load() -> Preferences {
        guard let data = UserDefaults.standard.data(forKey: key),
              let decoded = try? JSONDecoder().decode(Preferences.self, from: data)
        else { return Preferences() }
        return decoded
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.key)
    }
}
