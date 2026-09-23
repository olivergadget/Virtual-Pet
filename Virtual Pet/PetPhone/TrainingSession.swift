import Foundation
import SwiftUI

/// Tuning for a lesson: how many goes it runs for, and how forgiving the hand signals
/// are. Distances are in points and speeds in points per second.
enum TrainingTuning {
    /// Cues in one lesson.
    static let repsPerSession = 5
    /// How long the pet spends working out what you meant before it tries.
    static let thinkingTime: TimeInterval = 0.55
    /// How long there is to say well done before the moment passes.
    static let praiseWindow: TimeInterval = 2.6
    /// The beat the pet spends looking pleased with itself after being praised.
    static let praiseBeat: TimeInterval = 0.9
    /// How long a fumble is left on screen before the next cue.
    static let fumbleTime: TimeInterval = 1.8

    // Hand signal recognition.
    /// How far a hand has to travel for a swipe or a flick to count.
    static let swipeDistance: Double = 88
    /// How far a vertical signal may wander sideways and still read as vertical.
    static let swipeDrift: Double = 80
    /// A flick has to be at least this quick, which is what separates it from a swipe.
    static let flickSpeed: Double = 520
    /// How long a flat palm has to stay put.
    static let holdTime: TimeInterval = 0.9
    /// How far a "still" hand is allowed to drift.
    static let holdSlack: Double = 34
    /// Longest contact that still counts as a tap rather than a press.
    static let tapWindow: TimeInterval = 0.4
    /// Longest gap between the two taps of a double tap.
    static let doubleTapGap: TimeInterval = 0.75
    /// Degrees of turning that add up to a circle.
    static let circleSweep: Double = 300
    /// Shortest path that can be a circle rather than a twitch.
    static let circleSize: Double = 150
    /// How far each leg of a there-and-back sweep has to run.
    static let sweepLeg: Double = 90
    /// A gesture longer than this that matched nothing leaves the pet baffled. Anything
    /// shorter is treated as a stray touch and ignored.
    static let muddleDistance: Double = 54
}

/// Watches the finger and decides whether it has drawn one particular hand signal.
///
/// Every signal is judged on its own terms — held still, swiped, flicked, circled, tapped
/// twice or swept there and back — from the same handful of measurements taken off the
/// path: how far it went, how far it strayed, how fast, and how much it turned.
struct SignalReader {
    let signal: HandSignal

    /// 0...1, how much of the signal has been drawn, for the progress ring.
    private(set) var progress: Double = 0
    private(set) var hasMatched = false
    /// True once the hand has plainly drawn something that isn't the signal.
    private(set) var isMuddled = false
    private(set) var isTouching = false

    // Measurements for the current contact.
    private var start: CGPoint = .zero
    private var previous: CGPoint = .zero
    private var contactTime: TimeInterval = 0
    private var pathLength: Double = 0
    /// Furthest the hand has strayed from where it started.
    private var wander: Double = 0
    private var speed: Double = 0
    private var lastMoveAt: TimeInterval?
    /// Signed degrees of turning accumulated along the path.
    private var turning: Double = 0
    private var heading: Double?
    /// Completed legs of a there-and-back sweep, and the turning point of the current one.
    private var legs = 0
    private var legSign: Double = 0
    private var legExtreme: Double = 0

    // Taps survive between contacts: a double tap is two of them.
    private var taps = 0
    private var lastTapAt: TimeInterval?

    init(signal: HandSignal) {
        self.signal = signal
    }

    // MARK: Input

    mutating func move(to point: CGPoint) {
        guard !hasMatched else { return }

        guard isTouching else {
            beginContact(at: point)
            evaluate()
            return
        }

        let step = hypot(point.x - previous.x, point.y - previous.y)
        pathLength += step
        wander = max(wander, hypot(point.x - start.x, point.y - start.y))

        let now = Date.now.timeIntervalSinceReferenceDate
        if let lastMoveAt, now > lastMoveAt {
            // Clamped so neither a long gap between samples nor a burst of coalesced ones
            // reads as the wrong speed.
            let elapsed = min(max(now - lastMoveAt, 1.0 / 120.0), 0.1)
            speed = speed * 0.5 + (step / elapsed) * 0.5
        }
        lastMoveAt = now

        // Sub-pixel jitter would otherwise fill the turning total with noise.
        if step > 1 {
            accumulateTurning(to: point)
            accumulateLegs(at: point)
        }
        previous = point
        evaluate()
    }

    mutating func liftFinger() {
        guard isTouching else { return }
        isTouching = false

        let wasTap = contactTime <= TrainingTuning.tapWindow && pathLength < TrainingTuning.holdSlack
        if signal == .doubleTap, wasTap {
            registerTap()
        } else if !hasMatched, pathLength > TrainingTuning.muddleDistance || contactTime > 0.5 {
            // A real gesture that wasn't the signal. A brush of the screen is let off.
            isMuddled = true
        }

        if !hasMatched, signal != .doubleTap {
            progress = 0
        }
        lastMoveAt = nil
    }

    /// A hand held perfectly still stops sending movement, so holds are timed here.
    mutating func tick(_ step: TimeInterval) {
        guard isTouching, !hasMatched else { return }
        contactTime += step
        guard signal == .pressAndHold else { return }
        evaluate()
    }

    private mutating func beginContact(at point: CGPoint) {
        isTouching = true
        start = point
        previous = point
        contactTime = 0
        pathLength = 0
        wander = 0
        speed = 0
        lastMoveAt = nil
        turning = 0
        heading = nil
        legs = 0
        legSign = 0
        legExtreme = 0
        isMuddled = false
        if signal != .doubleTap { progress = 0 }
    }

    // MARK: Recognition

    private mutating func evaluate() {
        let dx = previous.x - start.x
        let dy = previous.y - start.y

        switch signal {
        case .pressAndHold:
            // A hand that has wandered off isn't holding anything; it gets judged on lift.
            guard wander <= TrainingTuning.holdSlack else {
                progress = 0
                return
            }
            progress = min(contactTime / TrainingTuning.holdTime, 1)
            if progress >= 1 { hasMatched = true }

        case .swipeDown:
            progress = min(max(dy / TrainingTuning.swipeDistance, 0), 1)
            if dy >= TrainingTuning.swipeDistance, abs(dx) <= TrainingTuning.swipeDrift {
                hasMatched = true
            }

        case .flickUp:
            progress = min(max(-dy / TrainingTuning.swipeDistance, 0), 1)
            if -dy >= TrainingTuning.swipeDistance, abs(dx) <= TrainingTuning.swipeDrift,
               speed >= TrainingTuning.flickSpeed {
                hasMatched = true
            }

        case .circle:
            progress = min(abs(turning) / TrainingTuning.circleSweep, 1)
            if abs(turning) >= TrainingTuning.circleSweep, pathLength >= TrainingTuning.circleSize {
                hasMatched = true
            }

        case .doubleTap:
            progress = max(progress, Double(taps) / 2)

        case .sweepAcross:
            progress = min(Double(legs) / 2, 1)
            if legs >= 2 { hasMatched = true }
        }

        if hasMatched { progress = 1 }
    }

    /// Turning is summed with its sign, so a scribble cancels itself out while a circle
    /// keeps adding up.
    private mutating func accumulateTurning(to point: CGPoint) {
        let angle = atan2(point.y - previous.y, point.x - previous.x) * 180 / .pi
        defer { heading = angle }
        guard let heading else { return }

        var delta = angle - heading
        // Kept inside -180...180, so wrapping past due west isn't a half turn.
        while delta > 180 { delta -= 360 }
        while delta < -180 { delta += 360 }
        turning += delta
    }

    /// A leg is a long run in one direction across the glass; the sweep needs two of them.
    private mutating func accumulateLegs(at point: CGPoint) {
        guard legSign != 0 else {
            let travel = point.x - start.x
            guard abs(travel) >= TrainingTuning.sweepLeg else { return }
            legSign = travel > 0 ? 1 : -1
            legs = 1
            legExtreme = point.x
            return
        }

        // Carrying on the same way just extends the leg already under way.
        if (point.x - legExtreme) * legSign > 0 {
            legExtreme = point.x
            return
        }
        // Doubling back far enough starts the next one.
        if abs(point.x - legExtreme) >= TrainingTuning.sweepLeg {
            legs += 1
            legSign *= -1
            legExtreme = point.x
        }
    }

    private mutating func registerTap() {
        let now = Date.now.timeIntervalSinceReferenceDate
        if let lastTapAt, now - lastTapAt <= TrainingTuning.doubleTapGap {
            taps = 2
        } else {
            taps = 1
        }
        lastTapAt = now
        progress = Double(taps) / 2
        if taps >= 2 { hasMatched = true }
    }
}

enum TrainingPhase {
    /// The cue is up and the hand signal is waiting to be drawn.
    case cue
    /// The signal was read; the pet is working out what you want.
    case thinking
    /// Performing the trick, or something adjacent to it.
    case performing
    /// It got it right, and is waiting to be told so.
    case praising
    /// It got it wrong.
    case fumbled
}

/// One lesson: a handful of cues, a hand signal to draw for each, and a pet that either
/// gets it or looks at you blankly.
///
/// The view owns one of these, feeds it touches, and awaits `run()` for the outcome.
@MainActor
@Observable
final class TrainingSession {
    let trick: TrickKind

    private(set) var phase: TrainingPhase = .cue
    /// Which cue of the lesson this is, from 1.
    private(set) var rep = 1
    private(set) var attempts = 0
    private(set) var successes = 0
    private(set) var praises = 0
    /// True once the pet has landed the trick for the first time ever.
    private(set) var isNewTrick = false
    /// 0...1 through the current routine, which drives the pose.
    private(set) var routine: Double = 0
    /// 0...1, how much of the hand signal has been drawn.
    private(set) var signalProgress: Double = 0
    /// True when the last thing drawn on the glass wasn't the signal at all.
    private(set) var isMuddled = false
    /// Seconds left to say well done.
    private(set) var praiseRemaining: TimeInterval = 0
    private(set) var didSucceed = false
    private(set) var wasPraised = false

    /// Rolls one attempt: the world applies the needs and the learning, and reports back
    /// whether the pet got it right.
    var onAttempt: ((TrickKind) -> TrickAttemptResult)?
    var onPraise: ((TrickKind) -> Void)?
    /// The hand drew something the pet couldn't read.
    var onMuddle: (() -> Void)?

    private var reader: SignalReader
    private var timer: TimeInterval = 0
    private var isFinished = false

    init(trick: TrickKind) {
        self.trick = trick
        self.reader = SignalReader(signal: trick.signal)
    }

    // MARK: Derived state

    /// The pet's pose right now, whether it is performing, celebrating or baffled.
    var pose: TrickPose {
        switch phase {
        case .cue, .thinking:
            .neutral
        case .performing, .praising, .fumbled:
            didSucceed ? .performing(trick, progress: routine) : .fumbling(progress: routine)
        }
    }

    var isWaitingForSignal: Bool { phase == .cue }

    // MARK: Input

    /// Every touch in the arena comes through here: while the cue is up it is read as a
    /// hand signal, and once the trick has landed it is a pat on the head.
    func touch(at point: CGPoint) {
        switch phase {
        case .cue:
            reader.move(to: point)
            syncReader()
        case .praising:
            praise()
        case .thinking, .performing, .fumbled:
            break
        }
    }

    func liftFinger() {
        guard phase == .cue else { return }
        reader.liftFinger()
        syncReader()
    }

    /// Says well done, which is what makes the trick stick.
    func praise() {
        guard phase == .praising, !wasPraised else { return }
        wasPraised = true
        praises += 1
        onPraise?(trick)
        // A short beat of the pet being pleased with itself, then on to the next cue.
        praiseRemaining = min(praiseRemaining, TrainingTuning.praiseBeat)
    }

    /// Ends the lesson early, from the Done button.
    func finish() {
        isFinished = true
    }

    // MARK: Simulation

    /// Runs the lesson until every cue has been worked through, `finish()` is called, or
    /// the task is cancelled, then reports how it went.
    func run() async -> TrainingOutcome {
        var last = Date.now.timeIntervalSinceReferenceDate
        while !isFinished, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { break }
            let now = Date.now.timeIntervalSinceReferenceDate
            let step = min(max(now - last, 0), 0.05)
            last = now
            advance(by: step)
        }
        return TrainingOutcome(trick: trick, attempts: attempts, successes: successes,
                               praises: praises, isNewTrick: isNewTrick)
    }

    private func advance(by step: TimeInterval) {
        guard step > 0 else { return }

        switch phase {
        case .cue:
            reader.tick(step)
            syncReader()

        case .thinking:
            timer -= step
            if timer <= 0 { attempt() }

        case .performing:
            routine = min(routine + step / trick.routineLength, 1)
            if routine >= 1 {
                if didSucceed {
                    phase = .praising
                    praiseRemaining = TrainingTuning.praiseWindow
                } else {
                    phase = .fumbled
                    timer = TrainingTuning.fumbleTime
                }
            }

        case .praising:
            praiseRemaining = max(praiseRemaining - step, 0)
            if praiseRemaining == 0 { nextCue() }

        case .fumbled:
            timer -= step
            if timer <= 0 { nextCue() }
        }
    }

    /// Pulls the reader's verdict into observable state, and starts the attempt once the
    /// signal has been drawn.
    private func syncReader() {
        signalProgress = reader.progress

        if reader.isMuddled {
            isMuddled = true
            onMuddle?()
            // A fresh reader, so the same muddle isn't reported twice.
            reader = SignalReader(signal: trick.signal)
            signalProgress = 0
            return
        }

        guard reader.hasMatched else { return }
        isMuddled = false
        phase = .thinking
        timer = TrainingTuning.thinkingTime
    }

    private func attempt() {
        attempts += 1
        let result = onAttempt?(trick) ?? .missed
        didSucceed = result.succeeded
        if result.succeeded { successes += 1 }
        if result.isNew { isNewTrick = true }
        routine = 0
        phase = .performing
    }

    private func nextCue() {
        guard rep < TrainingTuning.repsPerSession else {
            isFinished = true
            return
        }
        rep += 1
        didSucceed = false
        wasPraised = false
        isMuddled = false
        routine = 0
        signalProgress = 0
        reader = SignalReader(signal: trick.signal)
        phase = .cue
    }
}
