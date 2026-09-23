import Foundation
import SwiftUI

/// Tuning for the pour-and-eat feeding session. Positions are in points, rates per second.
enum MealTuning {
    /// Pieces of food that fill the bowl to the brim. One piece is one mouthful.
    static let bowlCapacity = PetRules.bitesPerBowl
    /// Pieces in a fresh bag. More than a bowlful, but not by much — aim carefully.
    static let bagCapacity = 40
    /// Pieces leaving the bag per second while it is tipped over.
    static let pourRate: Double = 10
    /// Mouthfuls per second once the pet has its head in the bowl.
    static let eatRate: Double = 3.2
    /// Downward acceleration on anything in the air.
    static let gravity: Double = 1_500
    /// How quickly the bag tips over and rights itself again, in full tilts per second.
    static let tipRate: Double = 3.4
    /// The bag has to be tipped this far before any food comes out of it.
    static let pourThreshold: Double = 0.5
    /// Full tilt, in degrees: enough to bring the mouth of the bag round and downwards.
    static let fullTilt: Double = 130
    /// Distance from the middle of the bag to its mouth.
    static let bagMouthReach: Double = 60
    /// The bag rides above the fingertip, so a thumb never covers the food.
    static let fingerLift: Double = 64
    /// Speed food leaves the mouth of the bag at.
    static let pourSpeed: Double = 70
    /// Sideways scatter given to food as it leaves the bag.
    static let pourScatter: Double = 38
    /// The bowl's on-screen size, and the share of its height taken up by the rim.
    static let bowlWidth: Double = 168
    static let bowlHeight: Double = 70
    static let bowlRimRatio: Double = 0.34
    /// Food landing further than this from the middle of the bowl misses it entirely.
    static let bowlHalfWidth: Double = 74
    /// How fast the pet trots to and from the bowl.
    static let petSpeed: Double = 250
    /// How far to the side of the bowl the pet stands while eating.
    static let feedingOffset: Double = 118
    /// The pet is drawn at full size and scaled down, so its shapes stay crisp.
    static let petScale: Double = 0.58
    /// Half the on-screen height of the pet, so its feet land on the floor.
    static let petHalfHeight: Double = 150 * petScale
    /// How far the pet keeps its shoulder from the edge of the screen.
    static let petEdgeInset: Double = 96
    /// A quiet beat with nothing left to do before the session bows out by itself.
    static let finishDelay: TimeInterval = 1.8
    /// How cross one piece of food on the floor makes the pet.
    static let annoyancePerSpill: Double = 0.16
    /// How fast being cross wears off, per second.
    static let annoyanceDecay: Double = 0.34
    /// Above this, the pet stands back and won't touch the bowl until it calms down.
    static let sulkThreshold: Double = 0.4
}

/// One piece of food: in the air out of the bag, or settled on the floor.
struct Kibble: Identifiable, Sendable {
    let id = UUID()
    var position: CGPoint
    var velocity: CGSize = .zero
    /// Fixed per piece, so a settled pile doesn't shimmer between frames.
    let size: Double
    let spin: Double
    /// True once a piece has bounced off a brimming bowl, so it can't land in it later.
    var hasBounced = false
}

/// How a meal went, in pieces of food.
struct MealOutcome: Sendable {
    let eaten: Int
    let spilled: Int
    let leftInBowl: Int
}

/// The state of one feeding session: a bag of food you tip into a bowl, and a pet that
/// comes over to eat whatever actually landed in it.
///
/// The view owns one of these, feeds it drag locations, and awaits `run()` for the tally.
@MainActor
@Observable
final class MealSession {
    // MARK: Bag

    private(set) var bagPosition: CGPoint = .zero
    /// The mouth of the bag, where food comes out.
    private(set) var spout: CGPoint = .zero
    /// 0 upright, 1 tipped right over.
    private(set) var tip: Double = 0
    private(set) var isTouching = false
    private(set) var bagRemaining = MealTuning.bagCapacity

    // MARK: Food

    private(set) var falling: [Kibble] = []
    private(set) var spilled: [Kibble] = []
    /// Short-lived bits flying out of the bowl as the pet chews.
    private(set) var crumbs: [Kibble] = []
    private(set) var bowlPieces = 0
    private(set) var piecesEaten = 0
    private(set) var piecesSpilled = 0
    /// True once any food has left the bag, so the hints can move on.
    private(set) var hasPoured = false

    // MARK: Pet

    private(set) var petPosition: CGPoint = .zero
    /// 0 standing, 1 head right down in the bowl.
    private(set) var headDip: Double = 0
    /// Snaps to 1 on every mouthful and fades, driving the chewing bob.
    private(set) var chew: Double = 0
    /// 0...1, how cross the pet is about food going on the floor. Climbs with every piece
    /// missed and bleeds away over a few seconds.
    private(set) var annoyance: Double = 0
    /// Runs while the pet is sulking, so the view can shake its head at you.
    private(set) var sulkPhase: Double = 0
    /// True once the pet has had as much as it can hold.
    private(set) var isSated = false

    // MARK: Arena

    private(set) var arena: CGSize = .zero
    private(set) var floorY: Double = 0
    private(set) var bowlCenter: CGPoint = .zero

    /// Called for every mouthful. Returns false once the pet has had enough.
    var onBite: (() -> Bool)?
    /// Called each time a piece of food drops into the bowl.
    var onPour: (() -> Void)?
    /// Called each time food hits the floor instead, so the pet can complain about it.
    var onSpill: (() -> Void)?

    /// Where the fingertip is. The bag hangs off this so the spout stays under the finger.
    private var anchor: CGPoint = .zero
    private var pourCredit: Double = 0
    private var chewCredit: Double = 0
    private var idleTime: TimeInterval = 0
    private var isFinished = false

    // MARK: Derived state

    var isPouring: Bool { isTouching && tip > MealTuning.pourThreshold && bagRemaining > 0 }

    var isEating: Bool { headDip > 0.6 && bowlPieces > 0 && !isSated }

    /// Cross enough to stand back and refuse the bowl until it has got over it.
    var isSulking: Bool { annoyance > MealTuning.sulkThreshold }

    var bowlFill: Double { Double(bowlPieces) / Double(MealTuning.bowlCapacity) }

    var isBowlFull: Bool { bowlPieces >= MealTuning.bowlCapacity }

    var bagFill: Double { Double(bagRemaining) / Double(MealTuning.bagCapacity) }

    /// Degrees the bag is tipped over by.
    var tipAngle: Double { tip * MealTuning.fullTilt }

    /// Where the rim of the bowl sits, which is the height food has to reach to land in it.
    var bowlRimY: Double {
        bowlCenter.y - MealTuning.bowlHeight / 2
            + MealTuning.bowlHeight * MealTuning.bowlRimRatio / 2
    }

    /// The eyes follow the food: the bag while waiting, the bowl once eating. A sulking
    /// pet stops following anything and just looks straight at you.
    var gaze: CGSize {
        if isSulking { return .zero }
        let focus = headDip > 0.3 ? bowlCenter : spout
        return CGSize(
            width: min(max((focus.x - petPosition.x) / 120, -1), 1),
            height: min(max((focus.y - petPosition.y) / 120, -1), 1)
        )
    }

    // MARK: Input

    /// Sizes the arena, and lays out the floor, the bowl and everybody's starting spots.
    func setArena(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let isFirstLayout = arena == .zero
        arena = size
        floorY = size.height - 92
        bowlCenter = CGPoint(x: size.width * 0.33, y: floorY - MealTuning.bowlHeight / 2)

        if isFirstLayout {
            anchor = CGPoint(x: bowlCenter.x, y: size.height * 0.30)
            petPosition = CGPoint(x: waitingSpot, y: petY)
        } else {
            petPosition = CGPoint(x: min(max(petPosition.x, 40), max(size.width - 40, 40)), y: petY)
        }
        anchor = clampedAnchor(anchor)
        updateBag()
    }

    func moveBag(to point: CGPoint) {
        isTouching = true
        anchor = clampedAnchor(point)
        updateBag()
    }

    func liftFinger() {
        isTouching = false
    }

    /// Ends the session early, from the Done button.
    func finish() {
        isFinished = true
    }

    // MARK: Simulation

    /// Runs the meal until the pet is full, `finish()` is called, or the task is cancelled,
    /// then reports where all the food ended up.
    func run() async -> MealOutcome {
        var last = Date.now.timeIntervalSinceReferenceDate
        while !isFinished, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { break }
            let now = Date.now.timeIntervalSinceReferenceDate
            let step = min(max(now - last, 0), 0.05)
            last = now
            advance(by: step)
        }
        return MealOutcome(eaten: piecesEaten, spilled: piecesSpilled, leftInBowl: bowlPieces)
    }

    private func advance(by step: TimeInterval) {
        guard step > 0, arena != .zero else { return }

        // A drag gesture holds its touch even when the finger stops moving, so resting a
        // finger on the screen keeps the bag tipped over and the food coming.
        tip += ((isTouching ? 1 : 0) - tip) * min(step * MealTuning.tipRate, 1)
        updateBag()

        pourFood(step)
        advanceFood(step)
        movePet(step)
        checkForIdle(step)
    }

    /// Recomputes the bag from the fingertip, keeping the spout directly under the finger
    /// however far the bag is tipped — so you aim with your fingertip, not with the bag.
    private func updateBag() {
        let radians = tipAngle * .pi / 180
        let mouth = CGSize(
            width: MealTuning.bagMouthReach * sin(radians),
            height: -MealTuning.bagMouthReach * cos(radians)
        )
        bagPosition = CGPoint(x: anchor.x - mouth.width, y: anchor.y - MealTuning.fingerLift)
        spout = CGPoint(x: bagPosition.x + mouth.width, y: bagPosition.y + mouth.height)
    }

    private func pourFood(_ step: TimeInterval) {
        guard isPouring else {
            pourCredit = 0
            return
        }
        pourCredit += MealTuning.pourRate * step
        while pourCredit >= 1, bagRemaining > 0 {
            pourCredit -= 1
            bagRemaining -= 1
            hasPoured = true

            let radians = tipAngle * .pi / 180
            let direction = CGSize(width: sin(radians), height: -cos(radians))
            let scatter = Double.random(in: -MealTuning.pourScatter...MealTuning.pourScatter)
            falling.append(
                Kibble(
                    position: spout,
                    velocity: CGSize(
                        width: direction.width * MealTuning.pourSpeed + scatter,
                        height: direction.height * MealTuning.pourSpeed
                    ),
                    size: Double.random(in: 9...13),
                    spin: Double.random(in: -60...60)
                )
            )
        }
    }

    private func advanceFood(_ step: TimeInterval) {
        crumbs = crumbs.compactMap { crumb in
            var crumb = crumb
            crumb.velocity.height += MealTuning.gravity * step
            crumb.position.x += crumb.velocity.width * step
            crumb.position.y += crumb.velocity.height * step
            // Crumbs are decoration, not waste: they vanish rather than joining the pile.
            return crumb.position.y >= floorY ? nil : crumb
        }

        guard !falling.isEmpty else { return }

        var landed = 0
        var settled: [Kibble] = []

        falling = falling.compactMap { piece in
            var piece = piece
            piece.velocity.height += MealTuning.gravity * step
            piece.position.x += piece.velocity.width * step
            piece.position.y += piece.velocity.height * step

            let isOverBowl = abs(piece.position.x - bowlCenter.x) <= MealTuning.bowlHalfWidth
            if isOverBowl, !piece.hasBounced, piece.position.y >= bowlRimY {
                if bowlPieces + landed < MealTuning.bowlCapacity {
                    landed += 1
                    return nil
                }
                // The bowl is brimming, so this one skitters off the heap and onto the floor.
                piece.hasBounced = true
                piece.velocity.width += piece.position.x < bowlCenter.x ? -210 : 210
                piece.velocity.height = -150
                return piece
            }

            if piece.position.y >= floorY {
                var resting = piece
                resting.position.y = floorY
                resting.velocity = .zero
                settled.append(resting)
                return nil
            }
            return piece
        }

        if landed > 0 {
            bowlPieces = min(bowlPieces + landed, MealTuning.bowlCapacity)
            onPour?()
        }
        if !settled.isEmpty {
            piecesSpilled += settled.count
            spilled.append(contentsOf: settled)
            // The floor pile is only decoration, so cap what gets drawn.
            if spilled.count > 60 { spilled.removeFirst(spilled.count - 60) }

            // Food on the floor is a personal slight. Enough of it and the pet stands
            // back with its nose out of joint until you sort yourself out.
            annoyance = min(annoyance + MealTuning.annoyancePerSpill * Double(settled.count), 1)
            onSpill?()
        }
    }

    private func movePet(_ step: TimeInterval) {
        chew = max(chew - step * 4, 0)
        annoyance = max(annoyance - MealTuning.annoyanceDecay * step, 0)
        sulkPhase = isSulking ? sulkPhase + step : 0

        // The pet hangs back while food is raining down, then comes over for the bowl —
        // unless it's still cross about the last lot you put on the floor.
        let wantsBowl = !isSated && bowlPieces > 0 && !isPouring && !isSulking
        let target = wantsBowl ? feedingSpot : waitingSpot
        let distance = target - petPosition.x
        let stride = MealTuning.petSpeed * step
        petPosition.x += abs(distance) <= stride ? distance : (distance < 0 ? -stride : stride)

        let isAtBowl = wantsBowl && abs(target - petPosition.x) < 1.5
        headDip += ((isAtBowl ? 1 : 0) - headDip) * min(step * 5, 1)

        guard isAtBowl, headDip > 0.7, bowlPieces > 0, !isSated else {
            chewCredit = 0
            return
        }

        chewCredit += MealTuning.eatRate * step
        while chewCredit >= 1, bowlPieces > 0, !isSated {
            chewCredit -= 1
            bowlPieces -= 1
            piecesEaten += 1
            chew = 1
            scatterCrumbs()
            if onBite?() == false { isSated = true }
        }
    }

    /// A couple of bits flicked out of the bowl, so a mouthful is visible as well as felt.
    private func scatterCrumbs() {
        for _ in 0..<2 {
            crumbs.append(
                Kibble(
                    position: CGPoint(x: bowlCenter.x + Double.random(in: -30...30),
                                      y: bowlRimY - 6),
                    velocity: CGSize(width: Double.random(in: -190...190),
                                     height: Double.random(in: -320...(-190))),
                    size: Double.random(in: 6...9),
                    spin: Double.random(in: -70...70)
                )
            )
        }
    }

    /// Bows out once there is genuinely nothing left to do: the pet is full, or the bowl
    /// and the bag are both empty. Any touch on the screen resets the wait.
    private func checkForIdle(_ step: TimeInterval) {
        let hasFoodLeft = bowlPieces > 0 || bagRemaining > 0 || !falling.isEmpty
        guard isSated || !hasFoodLeft, !isTouching else {
            idleTime = 0
            return
        }
        idleTime += step
        if idleTime >= MealTuning.finishDelay { isFinished = true }
    }

    // MARK: Geometry

    /// Where the pet stands to eat: beside the bowl, facing into it.
    private var feedingSpot: Double {
        let edge = max(arena.width - MealTuning.petEdgeInset, MealTuning.petEdgeInset)
        return min(bowlCenter.x + MealTuning.feedingOffset, edge)
    }

    /// Where the pet waits while food is being poured, out of the way of the stream.
    private var waitingSpot: Double {
        max(min(bowlCenter.x + 230, arena.width - MealTuning.petEdgeInset), feedingSpot)
    }

    private var petY: Double { floorY - MealTuning.petHalfHeight + 8 }

    /// Keeps the fingertip somewhere the bag can actually be drawn, and above the bowl.
    private func clampedAnchor(_ point: CGPoint) -> CGPoint {
        let minY = MealTuning.fingerLift + 40
        let maxY = max(bowlRimY - 30, minY)
        let maxX = max(arena.width - 30, 30)
        return CGPoint(
            x: min(max(point.x, min(30, maxX)), maxX),
            y: min(max(point.y, minY), maxY)
        )
    }
}
