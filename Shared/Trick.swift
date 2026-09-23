import SwiftUI

/// A trick the pet can be taught. Each one pairs a word you say out loud with a hand
/// signal drawn on the glass, and only unlocks once the bond is deep enough for the pet
/// to sit still and pay attention.
enum TrickKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case sit
    case paw
    case speak
    case spin
    case jump
    case rollOver

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .sit: "Sit"
        case .paw: "Give a paw"
        case .speak: "Speak"
        case .spin: "Spin"
        case .jump: "Jump"
        case .rollOver: "Roll over"
        }
    }

    /// The word to say, shown large on the cue card.
    var cue: String {
        switch self {
        case .sit: "Sit!"
        case .paw: "Paw!"
        case .speak: "Speak!"
        case .spin: "Spin!"
        case .jump: "Up!"
        case .rollOver: "Roll over!"
        }
    }

    var symbolName: String {
        switch self {
        case .sit: "figure.seated.side"
        case .paw: "pawprint.fill"
        case .speak: "speaker.wave.2.fill"
        case .spin: "arrow.clockwise"
        case .jump: "arrow.up.circle.fill"
        case .rollOver: "arrow.triangle.2.circlepath"
        }
    }

    /// The hand signal that teaches this trick.
    var signal: HandSignal {
        switch self {
        case .sit: .swipeDown
        case .paw: .pressAndHold
        case .speak: .doubleTap
        case .spin: .circle
        case .jump: .flickUp
        case .rollOver: .sweepAcross
        }
    }

    /// Bond level the pet has to reach before this trick can be started. Tricks that ask
    /// the pet to leave the ground come late, when it trusts you with more than a sit.
    var requiredLevel: Int {
        switch self {
        case .sit, .paw: 1
        case .speak, .spin: 2
        case .jump: 3
        case .rollOver: 4
        }
    }

    /// How long the pet takes to perform the trick, in seconds.
    var routineLength: TimeInterval {
        switch self {
        case .sit: 1.3
        case .paw: 1.4
        case .speak: 1.2
        case .spin: 1.1
        case .jump: 1.0
        case .rollOver: 1.5
        }
    }
}

/// What the person actually does on the glass. The pet learns to read the hand, not the
/// word, so every trick has its own movement.
enum HandSignal: String, Sendable {
    /// A flat palm, held still.
    case pressAndHold
    case swipeDown
    case flickUp
    case circle
    case doubleTap
    /// Across the glass and back again.
    case sweepAcross

    var name: String {
        switch self {
        case .pressAndHold: "Flat palm, held"
        case .swipeDown: "Hand down"
        case .flickUp: "Quick flick up"
        case .circle: "A circle"
        case .doubleTap: "Two taps"
        case .sweepAcross: "Across and back"
        }
    }

    var instruction: String {
        switch self {
        case .pressAndHold: "hold a flat palm on the glass"
        case .swipeDown: "draw your hand down the glass"
        case .flickUp: "flick your hand up, sharply"
        case .circle: "draw a circle with your finger"
        case .doubleTap: "tap twice, quickly"
        case .sweepAcross: "sweep across the glass and back"
        }
    }

    var symbolName: String {
        switch self {
        case .pressAndHold: "hand.raised.fill"
        case .swipeDown: "arrow.down"
        case .flickUp: "arrow.up"
        case .circle: "circle.dashed"
        case .doubleTap: "hand.tap.fill"
        case .sweepAcross: "arrow.left.and.right"
        }
    }

    /// The signal drawn as a path, so the training screen can show it as a dashed guide
    /// with a dot running along it. Taps and holds are drawn as the spots to press.
    func guidePath(in size: CGSize) -> Path {
        let inset: Double = 14
        let midX = size.width / 2
        let midY = size.height / 2
        var path = Path()

        switch self {
        case .pressAndHold:
            // A dot that barely moves: the point is to stay put.
            path.addEllipse(in: CGRect(x: midX - 7, y: midY - 7, width: 14, height: 14))

        case .swipeDown:
            path.move(to: CGPoint(x: midX, y: inset))
            path.addLine(to: CGPoint(x: midX, y: size.height - inset))

        case .flickUp:
            path.move(to: CGPoint(x: midX, y: size.height - inset))
            path.addLine(to: CGPoint(x: midX, y: inset))

        case .circle:
            let diameter = max(min(size.height, size.width) - inset * 2, 20)
            path.addEllipse(in: CGRect(x: midX - diameter / 2, y: midY - diameter / 2,
                                       width: diameter, height: diameter))

        case .doubleTap:
            // Two spots, so the travelling dot hops from one to the other.
            for side in [-1.0, 1.0] {
                path.addEllipse(in: CGRect(x: midX + side * 34 - 9, y: midY - 9,
                                           width: 18, height: 18))
            }

        case .sweepAcross:
            path.move(to: CGPoint(x: inset, y: midY))
            path.addLine(to: CGPoint(x: size.width - inset, y: midY))
            path.addLine(to: CGPoint(x: inset, y: midY))
        }

        return path
    }
}

/// What the pet has picked up of one trick.
struct TrickRecord: Codable, Identifiable, Sendable, Equatable {
    var kind: TrickKind
    /// 0...1, how reliably the pet performs it on cue.
    var mastery: Double = 0
    var attempts: Int = 0
    var successes: Int = 0
    var startedAt: Date = .now
    var lastPractisedAt: Date = .now

    var id: String { kind.rawValue }

    /// A trick only counts as learned once the pet has actually got it right once.
    var isLearned: Bool { successes > 0 }

    var isReliable: Bool { mastery >= PetRules.reliableMastery }

    var masteryTitle: String {
        guard isLearned else { return "Not yet" }
        return switch mastery {
        case ..<0.25: "Just learning"
        case ..<0.5: "Getting the idea"
        case ..<0.7: "Pretty good"
        case ..<0.9: "Reliable"
        default: "Flawless"
        }
    }
}

/// What came of one attempt at a trick.
struct TrickAttemptResult: Sendable {
    var succeeded: Bool
    /// True when this is the first time the pet has ever got the trick right.
    var isNew: Bool

    static let missed = TrickAttemptResult(succeeded: false, isNew: false)
}

/// How a lesson went.
struct TrainingOutcome: Sendable {
    var trick: TrickKind
    var attempts: Int
    var successes: Int
    var praises: Int
    /// True when the pet got the trick right for the very first time in this lesson.
    var isNewTrick: Bool
}

extension Pet {
    func record(for kind: TrickKind) -> TrickRecord? {
        tricks.first { $0.kind == kind }
    }

    func mastery(of kind: TrickKind) -> Double {
        record(for: kind)?.mastery ?? 0
    }

    func knows(_ kind: TrickKind) -> Bool {
        record(for: kind)?.isLearned ?? false
    }

    /// Tricks the pet can actually do, the best ones first.
    var learnedTricks: [TrickRecord] {
        tricks.filter(\.isLearned).sorted { $0.mastery > $1.mastery }
    }

    /// Tricks the bond is deep enough to start teaching.
    var teachableTricks: [TrickKind] {
        TrickKind.allCases.filter { level >= $0.requiredLevel }
    }

    /// Tricks still out of reach, with the shortest wait first.
    var lockedTricks: [TrickKind] {
        TrickKind.allCases
            .filter { level < $0.requiredLevel }
            .sorted { $0.requiredLevel < $1.requiredLevel }
    }

    /// Odds of the pet getting a trick right on cue. Mastery does most of the work, but a
    /// pet that needs a nap can't concentrate however well it knows the trick.
    func chance(of kind: TrickKind) -> Double {
        let learned = PetRules.baseTrickChance + mastery(of: kind) * PetRules.masteryTrickChance
        let focus = 0.55 + 0.45 * needs.rest
        return min(max(learned * focus, 0.05), 0.97)
    }

    /// Banks one attempt at a trick. Getting it right teaches the most, but a muddled
    /// attempt still teaches something. `learning` scales the lesson: a full one while
    /// training, a fraction of it when the pet is just showing off.
    /// Returns true when this was the first time the pet ever got the trick right.
    @discardableResult
    mutating func recordTrickAttempt(_ kind: TrickKind, succeeded: Bool,
                                     learning: Double = 1, now: Date = .now) -> Bool {
        var record = self.record(for: kind) ?? TrickRecord(kind: kind, startedAt: now)
        let wasLearned = record.isLearned

        record.attempts += 1
        record.lastPractisedAt = now
        if succeeded {
            record.successes += 1
            record.mastery += PetRules.masteryPerSuccess * learning
        } else {
            record.mastery += PetRules.masteryPerFumble * learning
        }
        record.mastery = min(record.mastery, 1)
        store(record)

        return succeeded && !wasLearned
    }

    /// Praise straight after a success, which is what really makes a trick stick.
    mutating func recordTrickPraise(_ kind: TrickKind, now: Date = .now) {
        guard var record = record(for: kind) else { return }
        record.mastery = min(record.mastery + PetRules.masteryPerPraise, 1)
        record.lastPractisedAt = now
        store(record)
    }

    /// Tricks go rusty when they aren't practised, but they are never forgotten: a
    /// learned trick keeps a floor of mastery, so the pet always half-remembers it.
    mutating func rustTricks(hours: Double) {
        guard hours > 0, !tricks.isEmpty else { return }
        let loss = PetRules.masteryRustPerDay * (hours / 24)
        for index in tricks.indices where tricks[index].isLearned {
            tricks[index].mastery = max(tricks[index].mastery - loss, PetRules.masteryFloor)
        }
    }

    private mutating func store(_ record: TrickRecord) {
        if let index = tricks.firstIndex(where: { $0.kind == record.kind }) {
            tricks[index] = record
        } else {
            tricks.append(record)
        }
    }
}

// MARK: - Performing

/// How a pet is held partway through a trick. The numbers are applied to the drawn pet by
/// whichever screen is showing it, so the creature itself never has to know about tricks.
struct TrickPose: Equatable, Sendable {
    /// Points of vertical movement. Negative is up.
    var lift: Double = 0
    /// Degrees of rotation about the pet's own centre.
    var spin: Double = 0
    /// Degrees of lean, for a raised paw or a puzzled head tilt.
    var tilt: Double = 0
    var squashX: Double = 1
    var squashY: Double = 1

    static let neutral = TrickPose()

    /// The pose partway through a trick the pet is getting right. `progress` runs 0...1
    /// across the whole routine.
    static func performing(_ trick: TrickKind, progress: Double) -> TrickPose {
        let time = min(max(progress, 0), 1)
        // Most routines ease into the shape, hold it, then come back out of it.
        let held = hold(time)
        let arc = sin(.pi * time)
        var pose = TrickPose()

        switch trick {
        case .sit:
            pose.squashY = 1 - 0.20 * held
            pose.squashX = 1 + 0.11 * held
            pose.lift = 16 * held

        case .paw:
            // Weight shifted onto one side, with the paw bobbing in the air.
            pose.tilt = -13 * held + sin(time * .pi * 4) * 3 * held
            pose.lift = -5 * held
            pose.squashY = 1 - 0.05 * held

        case .speak:
            // Three sharp barks, each one bouncing the pet off the floor.
            let bark = max(sin(time * .pi * 3), 0)
            pose.lift = -18 * bark
            pose.squashY = 1 + 0.11 * bark
            pose.squashX = 1 - 0.07 * bark

        case .spin:
            pose.spin = 360 * smoothstep(time)
            pose.lift = -10 * arc

        case .jump:
            // Gather into a crouch, spring up and over, then squash on the landing. The
            // crouch and the landing are bumps rather than ends of the routine, so the
            // pet doesn't snap into or out of either one.
            let crouch = max(1 - abs(time - 0.10) / 0.10, 0)
            let flight = sin(.pi * min(max((time - 0.16) / 0.74, 0), 1))
            let land = max(1 - abs(time - 0.92) / 0.06, 0)
            pose.lift = -96 * flight
            pose.squashY = 1 + 0.15 * flight - 0.14 * crouch - 0.16 * land
            pose.squashX = 1 - 0.08 * flight + 0.10 * crouch + 0.12 * land

        case .rollOver:
            pose.spin = 360 * smoothstep(time)
            pose.lift = 26 * held
            pose.squashY = 1 - 0.12 * held
        }

        return pose
    }

    /// The pose for an attempt that went wrong: a puzzled little wobble, whatever the
    /// trick was supposed to be.
    static func fumbling(progress: Double) -> TrickPose {
        let time = min(max(progress, 0), 1)
        var pose = TrickPose()
        pose.tilt = sin(time * .pi * 3) * 10
        pose.lift = -6 * sin(.pi * time)
        return pose
    }

    /// A trapezoid with eased edges: 0 at both ends, 1 through the middle.
    private static func hold(_ time: Double, ramp: Double = 0.24) -> Double {
        smoothstep(time / ramp) * smoothstep((1 - time) / ramp)
    }

    private static func smoothstep(_ value: Double) -> Double {
        let time = min(max(value, 0), 1)
        return time * time * (3 - 2 * time)
    }
}

extension View {
    /// Poses a drawn pet partway through a trick.
    func trickPose(_ pose: TrickPose) -> some View {
        self
            .scaleEffect(x: pose.squashX, y: pose.squashY, anchor: .bottom)
            .rotationEffect(.degrees(pose.tilt))
            .rotationEffect(.degrees(pose.spin))
            .offset(y: pose.lift)
    }
}
