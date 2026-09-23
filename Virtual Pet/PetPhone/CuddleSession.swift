import Foundation
import SwiftUI

/// Tuning for the cuddle session. Speeds are in points per second.
enum CuddleTuning {
    /// Finger speed that counts as a proper stroke rather than a resting thumb.
    static let strokeSpeed: Double = 105
    /// Once stroking, the speed it can dip to before the pet counts it as stopped. The gap
    /// between this and `strokeSpeed` keeps a wavering hand from flickering the purr.
    static let calmFloorSpeed: Double = 72
    /// Past this the hand is scrubbing rather than stroking, and the pet takes offence.
    static let franticSpeed: Double = 950
    /// How long the scrubbing has to keep up before the pet takes it personally. Single
    /// samples routinely spike over the threshold, so only a sustained one counts.
    static let roughGrace: TimeInterval = 0.22
    /// How fast a remembered stroke speed bleeds away once the finger stops moving.
    static let speedDecay: Double = 6
    /// Seconds of steady stroking needed to make the pet drowsy.
    static let warmthTime: TimeInterval = 4.5
    /// How much warmth drains per second while nobody is stroking.
    static let warmthDecay: Double = 0.18
    /// How much faster it drains while the pet is being handled roughly.
    static let roughWarmthDecay: Double = 0.5
    /// Fraction of the pet the blanket must cover for the tuck to count.
    static let tuckCoverage: Double = 0.82
    /// How long the hand can stop before the pet starts complaining about it.
    static let fussGrace: TimeInterval = 0.9
    /// Gap between complaints while it is being ignored or left uncovered.
    static let fussRepeat: TimeInterval = 2.2
    /// How much of the blanket peeks above the bottom edge before it is pulled.
    static let blanketLip: Double = 108
    /// How far past the pet's head the blanket can be pulled.
    static let blanketOvershoot: Double = 46
    /// The quiet moment at the end, once the pet is tucked in.
    static let settleLength: TimeInterval = 2.0
    /// The pet's drawn size in the den.
    static let petSize = CGSize(width: 224, height: 240)
}

/// How a cuddle ended: how sleepy the pet got, and whether the blanket made it on.
struct CuddleOutcome: Sendable {
    var warmth: Double
    var tucked: Bool
}

enum CuddlePhase {
    /// Stroking the pet until it is sleepy enough to settle.
    case stroking
    /// Sleepy, waiting for the blanket to be pulled over.
    case tucking
    /// Tucked in and dozing off.
    case settled
}

/// The state of one cuddle: a pet that has to be stroked drowsy, and a blanket that then
/// has to be dragged over it.
///
/// The view owns one of these, feeds it touches, and awaits `run()` for the outcome.
@MainActor
@Observable
final class CuddleSession {
    private(set) var phase: CuddlePhase = .stroking
    /// 0...1, how close the pet is to dozing off under your hand.
    private(set) var warmth: Double = 0
    /// Smoothed speed of the stroking finger, so one jittery sample doesn't count as a stroke.
    private(set) var strokeSpeed: Double = 0
    private(set) var isStroking = false
    /// True while the stroking is calm and steady — moving, but not frantic. This, rather
    /// than the touch itself, is what the pet purrs to.
    private(set) var isSoothing = false
    /// True once the pet has been touched at all; the first hint depends on it.
    private(set) var hasStroked = false
    /// Where the pet's eyes should point, in -1...1 on each axis.
    private(set) var gaze: CGSize = .zero
    /// The y coordinate of the blanket's top edge, in arena coordinates.
    private(set) var blanketTop: Double = 0
    private(set) var isDraggingBlanket = false
    private(set) var isTucked = false
    /// 0...1, how far the pet has sunk into the blanket after a successful tuck.
    private(set) var snug: Double = 0
    /// True while the pet is complaining: the hand stopped, or the blanket came off again.
    private(set) var isFussing = false
    /// True when the complaint is about the blanket rather than the stroking.
    private(set) var hasLostBlanket = false

    /// Called on the main actor as the stroking settles into something calming, and again
    /// when it stops or turns rough, so the world can run the same purring and hearts it
    /// does on the home screen.
    var onSoothingBegan: (() -> Void)?
    /// The distance the finger travelled this sample, in points.
    var onStroke: ((Double) -> Void)?
    var onSoothingEnded: (() -> Void)?
    /// The pet has gone drowsy and the blanket is now in play.
    var onSleepy: (() -> Void)?
    var onTucked: (() -> Void)?
    /// One complaint: called when the fussing starts, then again every few seconds while
    /// it carries on.
    var onFuss: (() -> Void)?

    private var arena: CGSize = .zero
    private var lastTouch: CGPoint?
    private var lastStrokeAt: TimeInterval?
    private var dragStartTop: Double = 0
    private var settleRemaining: TimeInterval = CuddleTuning.settleLength
    private var isFinished = false
    /// Seconds the pet has been left unattended, reset by every stroke and tuck.
    private var neglectTime: TimeInterval = 0
    /// Seconds the hand has been scrubbing away above `franticSpeed`.
    private var overspeedTime: TimeInterval = 0
    private var nextFussAt: TimeInterval = CuddleTuning.fussGrace

    // MARK: Layout

    /// Where the pet sits in the arena. The model owns this so the blanket and the sprite
    /// agree on what "covered" means.
    var petFrame: CGRect {
        let size = CuddleTuning.petSize
        return CGRect(
            x: arena.width / 2 - size.width / 2,
            y: arena.height * 0.44 - size.height / 2,
            width: size.width,
            height: size.height
        )
    }

    /// The blanket hangs off the bottom of the screen, so it is drawn from its top edge
    /// down past the bottom however far it has been pulled.
    var blanketFrame: CGRect {
        CGRect(x: 0, y: blanketTop,
               width: arena.width,
               height: max(arena.height - blanketTop, 0) + CuddleTuning.blanketLip)
    }

    /// Where the blanket rests before it is pulled.
    private var restingTop: Double { arena.height - CuddleTuning.blanketLip }

    /// Where the blanket ends up once the pet is tucked in.
    private var tuckedTop: Double { petFrame.minY - CuddleTuning.blanketOvershoot }

    // MARK: Derived state

    /// 0...1, how much of the pet the blanket currently hides.
    var coverage: Double {
        guard petFrame.height > 0 else { return 0 }
        return min(max((petFrame.maxY - blanketTop) / petFrame.height, 0), 1)
    }

    /// True once the hand has been going at the pet too fast to be relaxing for long
    /// enough to count as handling rather than a stray flick.
    var isTooRough: Bool { overspeedTime >= CuddleTuning.roughGrace }

    /// True once the blanket is far enough up that letting go would tuck the pet in.
    var isCoveringPet: Bool { coverage >= CuddleTuning.tuckCoverage }

    var canTuck: Bool { phase == .tucking }

    // MARK: Input

    func setArena(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        arena = size
        // A rotation mid-cuddle shouldn't yank the blanket out of the person's hand.
        guard !isDraggingBlanket else { return }
        blanketTop = isTucked ? tuckedTop : restingTop
    }

    func stroke(at point: CGPoint) {
        guard phase == .stroking else { return }
        isStroking = true
        hasStroked = true

        let now = Date.now.timeIntervalSinceReferenceDate
        if let lastTouch, let lastStrokeAt, now > lastStrokeAt {
            let travelled = hypot(point.x - lastTouch.x, point.y - lastTouch.y)
            // Clamped so neither a long gap between samples nor a burst of coalesced ones
            // reads as a frantic swipe.
            let elapsed = min(max(now - lastStrokeAt, 1.0 / 60.0), 0.1)
            strokeSpeed = strokeSpeed * 0.55 + (travelled / elapsed) * 0.45
            onStroke?(travelled)
        }
        lastTouch = point
        lastStrokeAt = now

        gaze = CGSize(
            width: min(max((point.x - petFrame.midX) / 120, -1), 1),
            height: min(max((point.y - petFrame.midY) / 120, -1), 1)
        )
    }

    func liftFinger() {
        guard isStroking else { return }
        isStroking = false
        lastTouch = nil
        lastStrokeAt = nil
        withAnimation(.easeOut(duration: 0.5)) { gaze = .zero }
        // `updateSoothing()` picks the lifted finger up on the next frame and tells the
        // world the stroking has stopped.
    }

    /// The blanket ignores the finger until the pet is sleepy.
    func grabBlanket() {
        guard canTuck, !isDraggingBlanket else { return }
        isDraggingBlanket = true
        dragStartTop = blanketTop
    }

    func dragBlanket(by translation: Double) {
        guard isDraggingBlanket else { return }
        let highest = min(tuckedTop, restingTop)
        blanketTop = min(max(dragStartTop + translation, highest), restingTop)
    }

    /// Let go: either the pet is covered and settles, or the blanket falls back down.
    func releaseBlanket() {
        guard isDraggingBlanket else { return }
        isDraggingBlanket = false
        if isCoveringPet {
            tuck()
        } else {
            // The blanket has slipped off again, which the pet has opinions about.
            hasLostBlanket = true
            neglectTime = 0
            nextFussAt = 0
            withAnimation(.spring(duration: 0.45)) { blanketTop = restingTop }
        }
    }

    /// Ends the session early, from the Done button.
    func finish() {
        isFinished = true
    }

    // MARK: Simulation

    /// Runs the cuddle until the pet is tucked in and dozing, `finish()` is called, or the
    /// task is cancelled, then reports how it went.
    func run() async -> CuddleOutcome {
        var last = Date.now.timeIntervalSinceReferenceDate
        while !isFinished, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { break }
            let now = Date.now.timeIntervalSinceReferenceDate
            let step = min(max(now - last, 0), 0.05)
            last = now
            advance(by: step)
        }
        return CuddleOutcome(warmth: warmth, tucked: isTucked)
    }

    private func advance(by step: TimeInterval) {
        guard step > 0, arena != .zero else { return }

        // A drag gesture only reports movement, so a resting finger stops feeding in any
        // speed and this decay takes over within about half a second.
        strokeSpeed *= exp(-CuddleTuning.speedDecay * step)

        // Scrubbing has to be kept up to count, and forgiven twice as fast as it builds.
        if isStroking, strokeSpeed > CuddleTuning.franticSpeed {
            overspeedTime += step
        } else {
            overspeedTime = max(overspeedTime - step * 2, 0)
        }

        updateSoothing()

        switch phase {
        case .stroking:
            if isSoothing {
                warmth += step / CuddleTuning.warmthTime
            } else {
                // Being scrubbed at undoes the calm far faster than being left alone.
                let decay = isTooRough ? CuddleTuning.roughWarmthDecay : CuddleTuning.warmthDecay
                warmth -= step * decay
            }
            warmth = min(max(warmth, 0), 1)
            if warmth >= 1 {
                // Sleepy pets stay sleepy: no decay from here, so there is no rush with
                // the blanket.
                phase = .tucking
                liftFinger()
                updateSoothing()
                onSleepy?()
            }

        case .tucking:
            break

        case .settled:
            settleRemaining = max(settleRemaining - step, 0)
            if settleRemaining == 0 { isFinished = true }
        }

        updateFussing(step)
    }

    /// Decides whether the stroking counts as calming, and tells the world when that
    /// changes. The two speeds either side of the threshold give it some hysteresis, so a
    /// hand that wavers doesn't flicker the purr on and off.
    private func updateSoothing() {
        let wasSoothing = isSoothing
        if !isStroking || isTooRough {
            isSoothing = false
        } else {
            isSoothing = strokeSpeed > (wasSoothing ? CuddleTuning.calmFloorSpeed : CuddleTuning.strokeSpeed)
        }

        guard isSoothing != wasSoothing else { return }
        if isSoothing {
            onSoothingBegan?()
        } else {
            onSoothingEnded?()
        }
    }

    /// The pet notices being mishandled: the hand stops, or goes at it like a car wash, or
    /// the blanket slips off again. It grumbles, and keeps grumbling until you sort it out.
    private func updateFussing(_ step: TimeInterval) {
        let isAttended = switch phase {
        case .stroking: isSoothing || !hasStroked
        // Dragging the blanket about counts: the pet can see you are dealing with it.
        case .tucking: !hasLostBlanket || isDraggingBlanket
        case .settled: true
        }

        guard !isAttended else {
            neglectTime = 0
            nextFussAt = CuddleTuning.fussGrace
            isFussing = false
            return
        }

        neglectTime += step
        // Rough handling gets an instant first complaint; a hand that has merely stopped
        // gets a moment's grace. Once the grumbling has started, both settle into the same
        // steady repeat — pulling the schedule forward every frame would fire nonstop.
        if isTooRough, !isFussing { nextFussAt = min(nextFussAt, neglectTime) }
        guard neglectTime >= nextFussAt else { return }
        nextFussAt = neglectTime + CuddleTuning.fussRepeat
        isFussing = true
        onFuss?()
    }

    private func tuck() {
        isTucked = true
        phase = .settled
        onTucked?()
        withAnimation(.spring(duration: 0.6)) {
            blanketTop = tuckedTop
            snug = 1
        }
    }
}
