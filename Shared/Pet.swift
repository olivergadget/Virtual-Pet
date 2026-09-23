import Foundation
import SwiftUI
import WidgetKit

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

    // A feeding session pays out per mouthful, so a bowl filled carelessly feeds the pet
    // less than a bowl filled properly.
    static let bitesPerBowl = 24
    static let fullnessPerBite = fullnessPerMeal / Double(bitesPerBowl)
    static let bondPerBite = 0.16
    /// Above this much fullness the pet turns the bowl down.
    static let maximumFullnessToEat = 0.95
    /// Food on the floor is an insult, not just waste — but one bad pour shouldn't undo
    /// a whole evening of being nice to them.
    static let affectionLostPerSpill = 0.006
    static let maximumAffectionLostToSpills = 0.15

    // A play session pays out per pounce, so a lively chase is worth more than a limp one.
    static let funPerCatch = 0.055
    static let restCostPerCatch = 0.020
    static let fullnessCostPerCatch = 0.008
    static let bondPerCatch = 1.2
    /// Below this much rest the pet won't chase anything at all.
    static let minimumRestToPlay = 0.16

    // A cuddle pays out through the petting rules while you stroke; getting the blanket
    // over the pet at the end buys a chunk of rest on top.
    static let restPerTuckIn = 0.14
    static let affectionPerTuckIn = 0.16
    static let bondPerTuckIn = 4.0

    // Training. Mastery of a trick runs 0...1, where 1 is performed perfectly on cue.
    /// What the pet picks up from one attempt it got right. A trick takes several
    /// lessons: getting it perfect in an evening would be no fun at all.
    static let masteryPerSuccess = 0.07
    /// Even a muddled attempt teaches it something.
    static let masteryPerFumble = 0.015
    /// Praise straight after a success is what really makes a trick stick.
    static let masteryPerPraise = 0.05
    /// Mastery lost per day a trick goes unpractised.
    static let masteryRustPerDay = 0.04
    /// However rusty it gets, a learned trick never falls below this — the pet always
    /// half-remembers it.
    static let masteryFloor = 0.12
    /// At or above this the pet can be relied on to perform on the first ask.
    static let reliableMastery = 0.7
    /// Odds of getting a brand new trick right, before any of it has been learned.
    static let baseTrickChance = 0.3
    /// How much of the remaining odds mastery buys.
    static let masteryTrickChance = 0.65
    static let funPerTrickAttempt = 0.022
    static let restCostPerTrickAttempt = 0.018
    static let affectionPerPraise = 0.05
    static let bondPerTrickSuccess = 2.5
    static let bondPerPraise = 1.5
    /// Landing a trick for the very first time is the biggest moment in the app.
    static let bondPerNewTrick = 12.0
    static let bondPerShowOff = 1.0
    /// Showing off on the home screen is practice of a sort, but it is no substitute for
    /// a proper lesson, so it teaches a fraction as much.
    static let showOffLearning = 0.4
    /// Below this much rest the pet can't concentrate on a lesson at all.
    static let minimumRestToTrain = 0.22

    // Meeting another pet. Seeing a friend is the best thing that happens to a pet all
    // day, and it is paid accordingly.
    static let funPerReunion = 0.24
    static let affectionPerReunion = 0.16
    static let bondPerReunion = 6.0
    /// The reunion is a whole cutscene, so the same friend can't set another one off for
    /// this long — walking in and out of range shouldn't replay it.
    static let reunionCooldown: TimeInterval = 15 * 60

    // Postcards. Being on the front of one is, as far as the pet is concerned, the
    // proudest moment of its week.
    static let funPerPostcard = 0.10
    static let affectionPerPostcard = 0.06
    static let bondPerPostcard = 5.0
    /// A postcard turning up from somebody nearby. Worth something, but a fraction of
    /// being on one yourself.
    static let funPerPostcardSeen = 0.03
    /// Somebody liking a postcard of yours, which the pet takes as applause. Less than
    /// making the postcard was worth — a like is one tap — but it is the pet being
    /// admired, and that is the pet's favourite thing in the world.
    static let funPerLikeReceived = 0.05
    static let affectionPerLikeReceived = 0.04
    static let bondPerLikeReceived = 2.0
    /// How many likes arriving at once are actually paid for. A phone that has been out
    /// of range for a week turns up with the lot, and that shouldn't top the pet up.
    static let maximumLikesPaidAtOnce = 3.0
    /// Liking somebody else's postcard. Being sociable counts for a little.
    static let funPerLikeGiven = 0.02
    static let bondPerLikeGiven = 1.0

    // Real life. People sleep, and go to work or school, and a pet whose needs drain at
    // full speed through both is a pet you can only ever come back to find miserable —
    // through no fault of your own. So the pet keeps your hours instead: it sleeps when
    // you sleep, and dozes and waits while you're out. These scale the idle drift rates
    // above, per the phase the pet is in. See `PetSchedule`.
    /// Asleep, the pet is barely ticking over. Eight hours in bed costs it about what
    /// one waking hour does.
    static let asleepDrainScale = 0.12
    /// Out at work or school, the pet naps, pesters nobody, and waits. A school day
    /// costs about two and a half waking hours.
    static let awayDrainScale = 0.30
    /// A proper night's sleep is worth more rest than an afternoon in a pocket.
    static let asleepRestScale = 1.8
    static let awayRestScale = 1.2

    /// Idle drift stops here. Time alone can leave a pet sulky, hungry and plainly
    /// pleased to see you, and that is as far as it goes — there is no coming back to a
    /// hollowed-out pet because you had a long week. Things the person actually did (a
    /// spilled bowl, a game that ran the pet ragged) can still push below this, and drift
    /// will never top a need back up to reach it.
    static let idleDriftFloor = 0.2

    /// Needs only catch up over three days, so coming back after a holiday finds a sulky
    /// pet rather than a dead one. Nothing in this app ever dies.
    static let maximumCatchUp: TimeInterval = 60 * 60 * 72

    /// How long the phone must lie still before the pet notices it has been abandoned.
    static let setDownGracePeriod: TimeInterval = 40

    /// How often the pet is allowed to interrupt of its own accord — a greeting, a
    /// complaint about being put down, or a request for something. Every unprompted
    /// speech bubble goes through this one gate, so the pet checks in about once a
    /// quarter of an hour rather than every few seconds. Anything the person actually
    /// did still gets an immediate reply.
    static let promptInterval: TimeInterval = 15 * 60
}

/// What the pet is doing with the parts of the day you aren't in.
enum PetPhase: String, Codable, Sendable {
    /// Up, about, and wanting things at the full rate.
    case awake
    /// Asleep alongside you. Needs barely move and rest comes back quickly.
    case asleep
    /// You're at work or at school. The pet dozes, keeps one ear on the door, and waits.
    case away

    /// How fast needs fall in this phase, against an ordinary waking hour.
    var drainScale: Double {
        switch self {
        case .awake: 1
        case .asleep: PetRules.asleepDrainScale
        case .away: PetRules.awayDrainScale
        }
    }

    /// How fast rest comes back in this phase.
    var restScale: Double {
        switch self {
        case .awake: 1
        case .asleep: PetRules.asleepRestScale
        case .away: PetRules.awayRestScale
        }
    }

    var label: String {
        switch self {
        case .awake: "Awake"
        case .asleep: "Asleep"
        case .away: "Holding the fort"
        }
    }

    var symbolName: String {
        switch self {
        case .awake: "sun.max.fill"
        case .asleep: "moon.zzz.fill"
        case .away: "backpack.fill"
        }
    }
}

/// The pet's day, matched to the day of the person looking after it: the hours they're
/// asleep, and the hours they're at work or school. The pet keeps those hours too, so a
/// night's sleep and a school day cost it a fraction of what they used to. Nobody should
/// have to choose between a full night and a happy pet.
struct PetSchedule: Codable, Sendable, Equatable {
    /// Minutes past local midnight, so a schedule means the same thing after a flight as
    /// it did before one. A window whose start is later than its end wraps over midnight,
    /// which is the ordinary case for sleep and the night-shift case for work.
    var sleepStart: Int = 23 * 60
    var sleepEnd: Int = 7 * 60
    var awayStart: Int = 8 * 60 + 30
    var awayEnd: Int = 16 * 60
    var sleepEnabled = true
    var awayEnabled = true
    /// Weekends are yours. On for shifts and rotas that don't care what day it is.
    var awayEveryDay = false

    init() {}

    // Decoded defensively, for the same reason `Preferences` is: a schedule saved by an
    // older build is missing anything added since, and half a schedule would have the
    // pet keeping hours nobody asked for.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let fallback = PetSchedule()
        sleepStart = try container.decodeIfPresent(Int.self, forKey: .sleepStart) ?? fallback.sleepStart
        sleepEnd = try container.decodeIfPresent(Int.self, forKey: .sleepEnd) ?? fallback.sleepEnd
        awayStart = try container.decodeIfPresent(Int.self, forKey: .awayStart) ?? fallback.awayStart
        awayEnd = try container.decodeIfPresent(Int.self, forKey: .awayEnd) ?? fallback.awayEnd
        sleepEnabled = try container.decodeIfPresent(Bool.self, forKey: .sleepEnabled) ?? true
        awayEnabled = try container.decodeIfPresent(Bool.self, forKey: .awayEnabled) ?? true
        awayEveryDay = try container.decodeIfPresent(Bool.self, forKey: .awayEveryDay) ?? false
    }

    // MARK: Reading the clock

    /// Where the pet is in its day at `date`. Sleep wins over work: if you're up at 3am
    /// on a night shift, say so by moving bedtime rather than by overlapping the two.
    func phase(at date: Date, calendar: Calendar = .current) -> PetPhase {
        let minute = Self.minute(of: date, calendar: calendar)
        if sleepEnabled, Self.window(from: sleepStart, to: sleepEnd, contains: minute) {
            return .asleep
        }
        if awayEnabled, Self.window(from: awayStart, to: awayEnd, contains: minute),
           worksOnDay(of: date, minute: minute, calendar: calendar) {
            return .away
        }
        return .awake
    }

    /// Effective hours of idle drift across a span: the hours weighed by what the pet was
    /// doing in them, rather than merely counted. Returns one figure for the needs that
    /// drain and one for the rest that refills, because sleep does both at once.
    func driftHours(
        from start: Date,
        to end: Date,
        calendar: Calendar = .current
    ) -> (drain: Double, rest: Double) {
        var drain = 0.0
        var rest = 0.0
        var cursor = start

        // Walked one stretch at a time, because a single span can cross a bedtime, a
        // sunrise and a whole working day. A day holds a handful of boundaries at most
        // and the catch-up is capped at three days, so this is a few dozen steps in the
        // very worst case and one step on an ordinary tick.
        while cursor < end {
            let next = min(boundary(after: cursor, calendar: calendar) ?? end, end)
            guard next > cursor else { break }
            let phase = phase(at: cursor, calendar: calendar)
            let hours = next.timeIntervalSince(cursor) / 3600
            drain += hours * phase.drainScale
            rest += hours * phase.restScale
            cursor = next
        }
        return (drain, rest)
    }

    /// When the pet is next awake, for a moment that falls inside its sleeping hours.
    /// `nil` when there are no sleeping hours to escape, or none to escape them into.
    func nextWaking(after date: Date, calendar: Calendar = .current) -> Date? {
        var cursor = date
        // A schedule has at most a few boundaries a day, so a dozen steps clears any
        // night that has a morning on the other side of it.
        for _ in 0..<12 {
            guard let next = boundary(after: cursor, calendar: calendar) else { return nil }
            if phase(at: next, calendar: calendar) != .asleep { return next }
            cursor = next
        }
        return nil
    }

    /// When the phase the pet is in now gives way to the next one.
    func nextChange(after date: Date, calendar: Calendar = .current) -> Date? {
        let current = phase(at: date, calendar: calendar)
        var cursor = date
        for _ in 0..<12 {
            guard let next = boundary(after: cursor, calendar: calendar) else { return nil }
            if phase(at: next, calendar: calendar) != current { return next }
            cursor = next
        }
        return nil
    }

    // MARK: Boundaries

    /// Every minute of the day at which the pet's phase can turn over. Midnight is always
    /// in the list when weekends are off, because that's where the day of the week
    /// changes and with it whether there's a school run at all.
    private var boundaryMinutes: [Int] {
        var minutes: [Int] = []
        if sleepEnabled, sleepStart != sleepEnd {
            minutes.append(sleepStart)
            minutes.append(sleepEnd)
        }
        if awayEnabled, awayStart != awayEnd {
            minutes.append(awayStart)
            minutes.append(awayEnd)
            if !awayEveryDay { minutes.append(0) }
        }
        return minutes
    }

    /// The first moment after `date` at which the phase might change. Built out of the
    /// calendar rather than by adding seconds, so the clocks going forward doesn't move
    /// anybody's bedtime.
    private func boundary(after date: Date, calendar: Calendar) -> Date? {
        let minutes = boundaryMinutes
        guard !minutes.isEmpty else { return nil }

        let today = calendar.startOfDay(for: date)
        var soonest: Date?
        for dayOffset in 0...1 {
            guard let day = calendar.date(byAdding: .day, value: dayOffset, to: today) else { continue }
            for minute in minutes {
                guard let candidate = Self.date(forMinute: minute, on: day, calendar: calendar),
                      candidate > date else { continue }
                if let best = soonest, candidate >= best { continue }
                soonest = candidate
            }
        }
        return soonest
    }

    /// Whether the working day covering `date` is one the person actually works. A shift
    /// that runs past midnight belongs to the day it started on, so that's the day asked
    /// about — finishing at 2am on Saturday is still Friday's shift.
    private func worksOnDay(of date: Date, minute: Int, calendar: Calendar) -> Bool {
        guard !awayEveryDay else { return true }
        let started = awayStart > awayEnd && minute < awayEnd
            ? date.addingTimeInterval(-24 * 60 * 60)
            : date
        return !calendar.isDateInWeekend(started)
    }

    /// Half-open: the minute a window ends belongs to whatever comes next.
    private static func window(from start: Int, to end: Int, contains minute: Int) -> Bool {
        if start == end { return false }
        if start < end { return minute >= start && minute < end }
        // Wrapped over midnight.
        return minute >= start || minute < end
    }

    // MARK: Minutes and dates

    static let minutesPerDay = 24 * 60

    static func minute(of date: Date, calendar: Calendar = .current) -> Int {
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
    }

    private static func date(forMinute minute: Int, on day: Date, calendar: Calendar) -> Date? {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)
    }

    /// A minute past midnight as a `Date` on today's date, which is what a `DatePicker`
    /// needs to show it.
    static func time(forMinute minute: Int, calendar: Calendar = .current, now: Date = .now) -> Date {
        date(forMinute: minute, on: calendar.startOfDay(for: now), calendar: calendar) ?? now
    }

    /// A minute past midnight written the way the person's own clock writes it.
    static func label(forMinute minute: Int) -> String {
        time(forMinute: minute).formatted(date: .omitted, time: .shortened)
    }
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

    /// What this need actually does, for someone who has just met the pet.
    var explanation: String {
        switch self {
        case .affection:
            "Falls fastest of the four, and counts for most of the mood."
        case .fun:
            "Drains through the day. A bored pet goes restless and grumbles."
        case .fullness:
            "Empties slowly whether or not the app is open."
        case .rest:
            "Refills on its own while you leave the pet alone. Playing and lessons spend it."
        }
    }

    /// The thing to do about it when the meter goes red.
    var remedy: String {
        switch self {
        case .affection:
            "Stroke the pet with a finger, or Cuddle and tuck it in."
        case .fun:
            "Play a round of chase, or teach a trick from the trick book."
        case .fullness:
            "Feed a bowl — pour it carefully, every mouthful counts."
        case .rest:
            "Put the phone down for a while, or Cuddle until it drops off."
        }
    }

    /// The button or gesture the remedy points at.
    var remedySymbolName: String {
        switch self {
        case .affection: "hand.draw.fill"
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

/// The little business card a pet hands over when it meets another pet.
struct PetCard: Codable, Sendable, Identifiable, Equatable {
    var id: String
    var name: String
    var kind: PetKind
    var level: Int
    var moodLabel: String
    var headline: String
}

/// Everything the app remembers about a pet between launches.
struct Pet: Codable, Identifiable, Sendable {
    var id: UUID
    var name: String
    var kind: PetKind
    /// Colours and size, as chosen by the owner in the designer.
    var appearance: PetAppearance
    var bornAt: Date
    /// Last time the person did something caring: petting, feeding, playing or holding.
    var lastTendedAt: Date
    /// Last moment the simulation ran, so needs can catch up after the app was closed.
    var lastSimulatedAt: Date
    var needs: Needs
    var bondPoints: Double
    var friends: [FriendRecord]
    /// Tricks the pet has been taught, or is in the middle of learning.
    var tricks: [TrickRecord]
    /// The hours the owner sleeps and is out, which the pet keeps alongside them.
    var schedule: PetSchedule
    /// Where the pet considers home. Set from the first location fix, changeable in settings.
    var homeLatitude: Double?
    var homeLongitude: Double?

    init(name: String, kind: PetKind, appearance: PetAppearance = PetAppearance(), now: Date = .now) {
        self.id = UUID()
        self.name = name
        self.kind = kind
        self.appearance = appearance
        self.bornAt = now
        self.lastTendedAt = now
        self.lastSimulatedAt = now
        self.needs = Needs()
        self.bondPoints = 0
        self.friends = []
        self.tricks = []
        self.schedule = PetSchedule()
    }

    // Decoded defensively: a save file written by an older build is missing keys added
    // later, and a pet should survive an app update.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        name = try container.decodeIfPresent(String.self, forKey: .name) ?? "Friend"
        kind = try container.decodeIfPresent(PetKind.self, forKey: .kind) ?? .cat
        appearance = try container.decodeIfPresent(PetAppearance.self, forKey: .appearance) ?? PetAppearance()
        bornAt = try container.decodeIfPresent(Date.self, forKey: .bornAt) ?? .now
        lastTendedAt = try container.decodeIfPresent(Date.self, forKey: .lastTendedAt) ?? .now
        lastSimulatedAt = try container.decodeIfPresent(Date.self, forKey: .lastSimulatedAt) ?? .now
        needs = try container.decodeIfPresent(Needs.self, forKey: .needs) ?? Needs()
        bondPoints = try container.decodeIfPresent(Double.self, forKey: .bondPoints) ?? 0
        friends = try container.decodeIfPresent([FriendRecord].self, forKey: .friends) ?? []
        // A trick written by a newer build is one this one can't name, and losing the
        // trick list is a great deal better than losing the pet along with it.
        tricks = (try? container.decode([TrickRecord].self, forKey: .tricks)) ?? []
        // A pet adopted before the app knew about school runs gets the default hours,
        // which is the kindest guess available.
        schedule = try container.decodeIfPresent(PetSchedule.self, forKey: .schedule) ?? PetSchedule()
        homeLatitude = try container.decodeIfPresent(Double.self, forKey: .homeLatitude)
        homeLongitude = try container.decodeIfPresent(Double.self, forKey: .homeLongitude)
    }
}

extension Pet {
    var voice: VoiceProfile { kind.voice }
    /// The species' colours with the owner's choices laid over the top.
    var palette: PetPalette { appearance.palette(for: kind) }
    var noseColor: Color { kind.noseColor(accent: palette.accent) }

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

    /// What the pet is doing right now: up and about, asleep alongside you, or waiting
    /// out your working day.
    var phase: PetPhase { schedule.phase(at: .now) }

    var isAsleep: Bool { phase == .asleep }

    /// Advances idle drift up to `date`. Safe to call repeatedly; it only moves forward.
    mutating func advance(to date: Date) {
        let elapsed = min(max(date.timeIntervalSince(lastSimulatedAt), 0), PetRules.maximumCatchUp)
        lastSimulatedAt = date
        guard elapsed > 0.5 else { return }

        // The span is weighed rather than counted. Hours the pet spent asleep beside you,
        // or dozing through your shift, cost it a fraction of a waking hour — so a night's
        // sleep and a day at school no longer add up to a miserable pet by teatime.
        let drift = schedule.driftHours(from: date.addingTimeInterval(-elapsed), to: date)
        needs.fullness = Self.drained(needs.fullness, by: PetRules.fullnessDecayPerHour * drift.drain)
        needs.fun = Self.drained(needs.fun, by: PetRules.funDecayPerHour * drift.drain)
        needs.affection = Self.drained(needs.affection, by: PetRules.affectionDecayPerHour * drift.drain)
        needs.rest += PetRules.restRecoveryPerHour * drift.rest
        needs.clamp()
        // Skills are a longer game than appetite, and they rust in real days.
        rustTricks(hours: elapsed / 3600)
    }

    /// Idle drift with a floor under it: being left alone takes a need down to
    /// `PetRules.idleDriftFloor` and no further. A need already below the floor — spent on
    /// a hard game, or docked for a spilled bowl — is left exactly where it is, so drift
    /// can neither deepen it nor quietly refill it.
    private static func drained(_ value: Double, by amount: Double) -> Double {
        max(value - amount, min(value, PetRules.idleDriftFloor))
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
///
/// The file lives in the App Group container so the widgets can look in on the same
/// pet the app is looking after, rather than a stale copy of their own.
enum PetArchive {
    private static let fileName = "pet.json"
    /// Matches the App Group entitlement on both the app and the widget extension.
    static let appGroupIdentifier = "group.us.gilman.vpet"

    /// The shared container, or the app's own Application Support folder when the App
    /// Group isn't available — a pet only the app can see beats no pet at all.
    private static var fileURL: URL? {
        let shared = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier)
        guard let shared else { return privateFileURL }
        return petFolder(in: shared).appendingPathComponent(fileName)
    }

    /// Where pets lived before the widgets needed to see them.
    private static var privateFileURL: URL? {
        guard let base = try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ) else { return nil }
        return petFolder(in: base).appendingPathComponent(fileName)
    }

    private static func petFolder(in base: URL) -> URL {
        let folder = base.appendingPathComponent("PetPhone", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    static func load() -> Pet? {
        guard let fileURL else { return nil }
        guard let data = (try? Data(contentsOf: fileURL)) ?? rehome(into: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Pet.self, from: data)
    }

    /// Carries a pet saved by an older build into the shared container, so updating the
    /// app doesn't look like the pet ran away.
    private static func rehome(into fileURL: URL) -> Data? {
        guard let privateFileURL, privateFileURL != fileURL,
              let data = try? Data(contentsOf: privateFileURL) else { return nil }
        try? data.write(to: fileURL, options: .atomic)
        try? FileManager.default.removeItem(at: privateFileURL)
        return data
    }

    static func save(_ pet: Pet) {
        guard let fileURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = .prettyPrinted
        guard let data = try? encoder.encode(pet) else { return }
        try? data.write(to: fileURL, options: .atomic)
        WidgetCenter.shared.reloadAllTimelines()
    }

    static func erase() {
        if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
        if let privateFileURL { try? FileManager.default.removeItem(at: privateFileURL) }
        WidgetCenter.shared.reloadAllTimelines()
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
    /// Whether postcards go out to nearby phones. Off still leaves the feed working —
    /// your own postcards are simply kept to yourself.
    var postcardsEnabled = true

    private static let key = "PetPhone.preferences"

    init() {}

    // Decoded defensively. Swift's synthesised decoder treats a missing key as an error
    // rather than falling back to the property's default, so adding a toggle in a later
    // build would otherwise reset every other toggle somebody had set.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        soundEnabled = try container.decodeIfPresent(Bool.self, forKey: .soundEnabled) ?? true
        hapticsEnabled = try container.decodeIfPresent(Bool.self, forKey: .hapticsEnabled) ?? true
        overridesSilentSwitch = try container.decodeIfPresent(Bool.self, forKey: .overridesSilentSwitch) ?? true
        notificationsEnabled = try container.decodeIfPresent(Bool.self, forKey: .notificationsEnabled) ?? true
        nearbyEnabled = try container.decodeIfPresent(Bool.self, forKey: .nearbyEnabled) ?? true
        postcardsEnabled = try container.decodeIfPresent(Bool.self, forKey: .postcardsEnabled) ?? true
    }

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
