import Foundation
import SwiftUI

/// Tuning for the chase-the-toy minigame. Speeds are in points per second.
enum ChaseTuning {
    /// How long one session lasts, counted from the first touch.
    static let sessionLength: TimeInterval = 25
    /// Below this the toy is dead in the water and the pet stops caring about it.
    static let livelySpeed: Double = 90
    /// How fast a stationary toy's remembered speed bleeds away, per second.
    static let speedDecay: Double = 7
    /// Interest climbs at this rate while the toy is lively, and falls at the other while it isn't.
    static let interestRise: Double = 4.5
    static let interestFall: Double = 2.4
    /// Below this much interest the pet gives up and coasts to a halt.
    static let chaseThreshold: Double = 0.12
    /// Flat-out sprint speed. A hard flick can outrun this, which is rather the point.
    static let petTopSpeed: Double = 430
    /// How sharply the pet can change direction — higher corners tighter.
    static let petAgility: Double = 7
    /// Distance at which an interesting toy counts as caught.
    static let catchRadius: Double = 42
    /// Victory wiggle after a catch, during which the toy cannot be caught again.
    static let catchCooldown: TimeInterval = 0.8
    /// The toy rides above the fingertip so a thumb doesn't cover it.
    static let fingerLift: Double = 30
    /// Half the on-screen size of the pet, used to keep it inside the arena.
    static let petRadius: Double = 54
}

/// The state of one play session: a toy dragged by a fingertip, and a pet that only gives
/// chase while the toy is actually moving.
///
/// The view owns one of these, feeds it drag locations, and awaits `run()` for the score.
@MainActor
@Observable
final class ToyChase {
    private(set) var toy: CGPoint = .zero
    private(set) var petPosition: CGPoint = .zero
    /// The pet's current motion, in points per second on each axis.
    private(set) var velocity: CGSize = .zero
    /// Smoothed speed of the toy, so one jittery sample can't wake or bore the pet.
    private(set) var toySpeed: Double = 0
    /// 0...1, how committed the pet is to the chase right now.
    private(set) var interest: Double = 0
    private(set) var catches = 0
    private(set) var timeRemaining: TimeInterval = ChaseTuning.sessionLength
    private(set) var isTouching = false
    /// True once the person has touched the screen; the clock doesn't start before then.
    private(set) var hasStarted = false
    /// Fades 1 to 0 after a catch, driving the pounce squash.
    private(set) var celebration: Double = 0

    /// Called on the main actor for every successful pounce.
    var onCatch: (() -> Void)?

    private var arena: CGSize = .zero
    private var lastMoveAt: TimeInterval?
    private var catchCooldown: TimeInterval = 0
    private var isFinished = false

    // MARK: Derived state

    /// Where the pet's eyes should point, in -1...1 on each axis.
    var gaze: CGSize {
        CGSize(
            width: min(max((toy.x - petPosition.x) / 90, -1), 1),
            height: min(max((toy.y - petPosition.y) / 90, -1), 1)
        )
    }

    /// Degrees of lean, so the pet tips into a sprint.
    var lean: Double {
        min(max(velocity.width / ChaseTuning.petTopSpeed, -1), 1) * 12
    }

    /// 0...1, how lively the toy looks — drives its glow and wobble.
    var liveliness: Double {
        min(toySpeed / ChaseTuning.livelySpeed, 1)
    }

    var isChasing: Bool { interest > ChaseTuning.chaseThreshold }

    var isCelebrating: Bool { celebration > 0 }

    // MARK: Input

    /// Sizes the arena, and drops the pet and toy into it the first time round.
    func setArena(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let isFirstLayout = arena == .zero
        arena = size
        if isFirstLayout {
            petPosition = CGPoint(x: size.width / 2, y: size.height * 0.66)
            toy = CGPoint(x: size.width / 2, y: size.height * 0.22)
        } else {
            petPosition = clamped(petPosition, inset: ChaseTuning.petRadius)
            toy = clamped(toy, inset: 14)
        }
    }

    func moveToy(to point: CGPoint) {
        isTouching = true
        hasStarted = true

        let target = clamped(CGPoint(x: point.x, y: point.y - ChaseTuning.fingerLift), inset: 14)
        let now = Date.now.timeIntervalSinceReferenceDate
        if let lastMoveAt, now > lastMoveAt {
            let travelled = hypot(target.x - toy.x, target.y - toy.y)
            // Clamped so a long gap between samples doesn't read as a crawl.
            let elapsed = min(max(now - lastMoveAt, 1.0 / 120.0), 0.1)
            toySpeed = toySpeed * 0.55 + (travelled / elapsed) * 0.45
        }
        lastMoveAt = now
        toy = target
    }

    func liftFinger() {
        isTouching = false
        lastMoveAt = nil
    }

    /// Ends the session early, from the Done button.
    func finish() {
        isFinished = true
    }

    // MARK: Simulation

    /// Runs the chase until the clock runs out, `finish()` is called, or the task is
    /// cancelled, then reports how many catches the pet managed.
    func run() async -> Int {
        var last = Date.now.timeIntervalSinceReferenceDate
        while !isFinished, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { break }
            let now = Date.now.timeIntervalSinceReferenceDate
            let step = min(max(now - last, 0), 0.05)
            last = now
            advance(by: step)
        }
        return catches
    }

    private func advance(by step: TimeInterval) {
        guard step > 0, arena != .zero else { return }

        if hasStarted {
            timeRemaining = max(timeRemaining - step, 0)
            if timeRemaining == 0 { isFinished = true }
        }

        celebration = max(celebration - step / 0.6, 0)
        catchCooldown = max(catchCooldown - step, 0)

        // A drag gesture only reports movement, so holding the finger still stops feeding
        // the toy any speed and this decay takes over within about half a second.
        toySpeed *= exp(-ChaseTuning.speedDecay * step)

        let isLively = isTouching && toySpeed > ChaseTuning.livelySpeed
        let rate = isLively ? ChaseTuning.interestRise : ChaseTuning.interestFall
        interest += ((isLively ? 1 : 0) - interest) * min(step * rate, 1)

        let dx = toy.x - petPosition.x
        let dy = toy.y - petPosition.y
        let distance = hypot(dx, dy)

        var desired = CGSize.zero
        if isChasing, catchCooldown == 0, distance > 1 {
            let speed = ChaseTuning.petTopSpeed * interest
            desired = CGSize(width: dx / distance * speed, height: dy / distance * speed)
        }

        // Interest also sets how tightly the pet can corner: a bored pet just skids to a stop.
        let agility = ChaseTuning.petAgility * (0.35 + 0.65 * interest)
        let blend = min(step * agility, 1)
        velocity.width += (desired.width - velocity.width) * blend
        velocity.height += (desired.height - velocity.height) * blend

        petPosition = clamped(
            CGPoint(x: petPosition.x + velocity.width * step,
                    y: petPosition.y + velocity.height * step),
            inset: ChaseTuning.petRadius
        )

        if distance < ChaseTuning.catchRadius, interest > 0.3, catchCooldown == 0 {
            catches += 1
            celebration = 1
            catchCooldown = ChaseTuning.catchCooldown
            velocity = .zero
            // The pet stops to gloat, so the toy has to be flicked away and back again.
            interest = 0
            onCatch?()
        }
    }

    private func clamped(_ point: CGPoint, inset: Double) -> CGPoint {
        guard arena != .zero else { return point }
        // An arena narrower than the inset would invert the range, so keep the limits ordered.
        let maxX = max(arena.width - inset, inset)
        let maxY = max(arena.height - inset, inset)
        return CGPoint(
            x: min(max(point.x, min(inset, maxX)), maxX),
            y: min(max(point.y, min(inset, maxY)), maxY)
        )
    }
}
