import Foundation
import SwiftUI

/// Tuning for the reunion show: the wildly over-the-top moment two pets discover each
/// other in the same room. The beats run back to back, in seconds.
enum ReunionTuning {
    /// Rooted to the spot, vibrating, unable to believe it.
    static let spotLength: TimeInterval = 1.0
    /// Full sprint from opposite edges of the screen.
    static let chargeLength: TimeInterval = 0.85
    /// The collision itself.
    static let collisionLength: TimeInterval = 0.35
    /// Bouncing and shrieking around each other while the sky goes off.
    static let rompLength: TimeInterval = 2.8
    /// Banner, final volley, curtain call.
    static let finaleLength: TimeInterval = 3.2

    static let spotEnd: TimeInterval = ReunionTuning.spotLength
    static let chargeEnd: TimeInterval = ReunionTuning.spotEnd + ReunionTuning.chargeLength
    static let collisionEnd: TimeInterval = ReunionTuning.chargeEnd + ReunionTuning.collisionLength
    static let rompEnd: TimeInterval = ReunionTuning.collisionEnd + ReunionTuning.rompLength
    static let showEnd: TimeInterval = ReunionTuning.rompEnd + ReunionTuning.finaleLength

    /// Pets are drawn at 280×300 and scaled down so two of them fit on one stage.
    static let performerScale: Double = 0.5
    /// Anything past this and the oldest particles get dropped.
    static let maximumParticles = 300
    /// Gap between firework launches once the two of them are together.
    static let fireworkInterval: TimeInterval = 0.40
    /// Gap between excited noises, alternating between the two pets.
    static let cheerInterval: TimeInterval = 0.55
}

/// The symbols the show throws about. Drawn as tagged canvas symbols so each one keeps
/// its own colour without a filter per particle.
enum ReunionGlyph: String, CaseIterable, Sendable {
    case heart
    case sparkle
    case star
    case note
    case paw
    case bolt

    var symbolName: String {
        switch self {
        case .heart: "heart.fill"
        case .sparkle: "sparkles"
        case .star: "star.fill"
        case .note: "music.note"
        case .paw: "pawprint.fill"
        case .bolt: "bolt.heart.fill"
        }
    }

    var tint: Color {
        switch self {
        case .heart: Color(red: 1.00, green: 0.28, blue: 0.42)
        case .sparkle: Color(red: 1.00, green: 0.86, blue: 0.32)
        case .star: Color(red: 1.00, green: 0.78, blue: 0.18)
        case .note: Color(red: 0.58, green: 0.45, blue: 1.00)
        case .paw: Color(red: 0.42, green: 0.84, blue: 1.00)
        case .bolt: Color(red: 1.00, green: 0.45, blue: 0.75)
        }
    }

    static var random: ReunionGlyph { allCases.randomElement() ?? .heart }
}

/// Who is meeting whom. Handed to the reunion screen so it knows whose faces to draw and
/// how big a deal this particular meeting is.
struct ReunionCast: Identifiable, Sendable {
    let id = UUID()
    let friend: PetCard
    /// How many times these two have met, this one included.
    let meetings: Int
    let bondTitle: String

    var isFirstMeeting: Bool { meetings <= 1 }

    /// The other pet, rebuilt from its card. Only a name and a species travel between
    /// phones, so it turns up in its species' stock colours — and absolutely thrilled,
    /// because it is.
    var stageDouble: Pet {
        var double = Pet(name: friend.name, kind: friend.kind)
        double.needs = Needs(fullness: 1, fun: 1, affection: 1, rest: 1)
        return double
    }
}

/// The reunion show. Two pets spot each other from opposite sides of the screen, sprint
/// into a collision, then bounce around one another while fireworks, hearts and confetti
/// go off — because as far as these two are concerned, this is the best thing that has
/// ever happened.
///
/// The view owns one of these, sizes its stage, and awaits `run()`. Sound and haptics are
/// left to the world through `onCue`, the same way the other session models work.
@MainActor
@Observable
final class Reunion {
    /// Where the show has got to.
    enum Beat {
        /// Frozen, staring, eyes the size of dinner plates.
        case spotting
        /// Sprinting at each other.
        case charging
        /// Impact.
        case colliding
        /// Bouncing around each other while the sky goes off.
        case romping
        /// Banner, final volley, curtain call.
        case finale
        case over
    }

    /// A moment worth a noise or a buzz.
    enum Cue: Sendable {
        case gasp
        case charge
        case impact
        case cheer
        case friendCheer
        case firework
        case finale
    }

    /// One drawn pet on the stage.
    struct Performer {
        var position: CGPoint = .zero
        /// Degrees of tilt.
        var rotation: Double = 0
        var scale: Double = 1
        /// Above 1 is stretched wide and squat, below 1 is tall and thin.
        var squash: Double = 1
        /// How far off the ground, in points.
        var lift: Double = 0
    }

    enum ParticleStyle {
        /// A bright additive dot: the bulk of every firework.
        case spark
        /// A dot stretched along its own velocity, for dust and rising shells.
        case streak
        case confetti
        /// An expanding shockwave.
        case ring
        case glyph(ReunionGlyph)
    }

    struct Particle {
        var position: CGPoint
        var velocity: CGSize
        var life: TimeInterval
        var lifespan: TimeInterval
        var size: Double
        var style: ParticleStyle
        var hue: Double = 0
        var angle: Double = 0
        /// Degrees per second.
        var spin: Double = 0
        /// Points per second added to `size` — rings use this to expand.
        var growth: Double = 0
        var lineWidth: Double = 0
        var gravity: Double = 0
        /// Exponential velocity damping per second. Zero leaves it coasting.
        var drag: Double = 0
        /// Firework shells burst into sparks when the fuse runs out.
        var burstsOnDeath = false

        /// 0...1, fading out over the last stretch of its life.
        var fade: Double { min(life / max(lifespan * 0.4, 0.0001), 1) }
        var age: Double { 1 - life / max(lifespan, 0.0001) }
    }

    // MARK: Observable state

    private(set) var beat: Beat = .spotting
    private(set) var elapsed: TimeInterval = 0
    private(set) var mine = Performer()
    private(set) var theirs = Performer()
    private(set) var particles: [Particle] = []
    /// 0...1, how hard the whole stage is shaking.
    private(set) var shake: Double = 0
    /// 0...1 white blowout over everything, from the collision and the big bursts.
    private(set) var flash: Double = 0
    /// 0...1 growth of the sunbeams behind the pets.
    private(set) var glory: Double = 0

    /// Called on the main actor for every moment worth a noise.
    var onCue: ((Cue) -> Void)?

    // MARK: Private state

    private var stage: CGSize = .zero
    private var isFinished = false
    private var nextFireworkAt: TimeInterval = 0
    private var nextCheerAt: TimeInterval = 0
    /// Alternates the shrieking between the two pets.
    private var isFriendsTurn = false
    /// Where each pet was when the romp ended, so the finale can slide them into line.
    private var handOff: (mine: CGPoint, theirs: CGPoint)?

    // MARK: Layout

    /// Where the two of them end up, and the centre of every burst.
    private var centre: CGPoint {
        CGPoint(x: stage.width / 2, y: stage.height * 0.47)
    }

    /// How far apart they stand once they are side by side.
    private var separation: Double { min(stage.width * 0.30, 130) }

    /// Where each pet waits before the charge: as far out as the stage allows while still
    /// leaving a whole pet on screen, because half a face reads as a bug rather than a
    /// dramatic entrance.
    private var wing: Double {
        let drawnHalfWidth = 280 * ReunionTuning.performerScale / 2 * 1.12
        let roomy = max(stage.width * 0.34, separation + 56)
        return min(roomy, max(stage.width / 2 - drawnHalfWidth - 6, separation * 0.6))
    }

    // MARK: Input

    func setStage(_ size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        let isFirstLayout = stage == .zero
        stage = size
        if isFirstLayout {
            updatePerformers()
        }
    }

    /// Cuts to the end, from a tap on the screen.
    func skip() {
        isFinished = true
    }

    // MARK: Simulation

    /// Runs the show to the final curtain, or until `skip()` is called or the task is
    /// cancelled.
    func run() async {
        enter(.spotting)
        var last = Date.now.timeIntervalSinceReferenceDate
        while !isFinished, !Task.isCancelled {
            try? await Task.sleep(for: .milliseconds(16))
            guard !Task.isCancelled else { break }
            let now = Date.now.timeIntervalSinceReferenceDate
            let step = min(max(now - last, 0), 0.05)
            last = now
            advance(by: step)
        }
    }

    private func advance(by step: TimeInterval) {
        // Nothing can be placed until the view has told us how big the stage is.
        guard step > 0, stage != .zero else { return }

        elapsed += step
        shake = max(shake - step * 3.0, 0)
        flash = max(flash - step * 4.0, 0)
        glory = min(elapsed / ReunionTuning.spotEnd, 1)

        updateBeat()
        updatePerformers()
        updateParticles(step)
        spawnAmbience(step)

        if elapsed >= ReunionTuning.showEnd {
            isFinished = true
        }
    }

    private func updateBeat() {
        let next: Beat
        switch elapsed {
        case ..<ReunionTuning.spotEnd: next = .spotting
        case ..<ReunionTuning.chargeEnd: next = .charging
        case ..<ReunionTuning.collisionEnd: next = .colliding
        case ..<ReunionTuning.rompEnd: next = .romping
        case ..<ReunionTuning.showEnd: next = .finale
        default: next = .over
        }
        guard next != beat else { return }
        beat = next
        enter(next)
    }

    private func enter(_ beat: Beat) {
        switch beat {
        case .spotting:
            onCue?(.gasp)
            // Two exclamations, one over each head.
            for side in [-1.0, 1.0] {
                add(Particle(
                    position: CGPoint(x: centre.x + side * wing, y: centre.y - 84),
                    velocity: CGSize(width: 0, height: -26),
                    life: 0.9, lifespan: 0.9, size: 40,
                    style: .glyph(.sparkle), drag: 2.6
                ))
            }

        case .charging:
            onCue?(.charge)

        case .colliding:
            collide()

        case .romping:
            onCue?(.cheer)
            confetti(count: 50)

        case .finale:
            handOff = (mine.position, theirs.position)
            finale()

        case .over:
            break
        }
    }

    // MARK: Choreography

    private func updatePerformers() {
        guard stage != .zero else { return }

        switch beat {
        case .spotting:
            // Rooted to the spot, leaning back, vibrating with disbelief.
            let progress = progress(0, ReunionTuning.spotEnd)
            let jitter = sin(elapsed * 34) * 2.8 * progress
            for isMine in [true, false] {
                let side: Double = isMine ? -1 : 1
                var performer = Performer()
                performer.position = CGPoint(x: centre.x + side * wing, y: centre.y + jitter)
                performer.rotation = side * 9 * progress
                performer.scale = 1 + 0.12 * progress
                performer.squash = 1 - 0.06 * progress
                performer.lift = 0
                assign(performer, isMine: isMine)
            }

        case .charging:
            // Accelerating flat out, leaning into it, galloping.
            let progress = progress(ReunionTuning.spotEnd, ReunionTuning.chargeEnd)
            let eased = pow(progress, 2.1)
            let distance = wing + (separation * 0.42 - wing) * eased
            let gallop = abs(sin(progress * .pi * 3.2))
            for isMine in [true, false] {
                let side: Double = isMine ? -1 : 1
                var performer = Performer()
                performer.position = CGPoint(x: centre.x + side * distance, y: centre.y)
                performer.rotation = -side * (8 + 16 * eased)
                performer.scale = 1 + 0.1 * eased
                performer.squash = 1 + 0.22 * eased
                performer.lift = gallop * 20
                assign(performer, isMine: isMine)
            }

        case .colliding:
            // Squashed flat against each other, then rebounding.
            let progress = progress(ReunionTuning.chargeEnd, ReunionTuning.collisionEnd)
            let impact = 1 - progress
            let recoil = sin(progress * .pi) * 24
            for isMine in [true, false] {
                let side: Double = isMine ? -1 : 1
                var performer = Performer()
                performer.position = CGPoint(x: centre.x + side * (separation * 0.34 + recoil),
                                            y: centre.y)
                performer.rotation = -side * 26 * impact
                performer.scale = 1 + 0.26 * impact
                performer.squash = 1 + 0.42 * impact
                performer.lift = 0
                assign(performer, isMine: isMine)
            }

        case .romping:
            // Orbiting each other, bouncing, spinning, completely beside themselves.
            let time = elapsed - ReunionTuning.collisionEnd
            let angle = time * 5.0
            let radius = separation * 0.56
            for isMine in [true, false] {
                let phase = angle + (isMine ? 0 : .pi)
                let bounce = abs(sin(time * 8 + (isMine ? 0 : .pi / 2)))
                var performer = Performer()
                performer.position = CGPoint(x: centre.x + cos(phase) * radius,
                                             y: centre.y + sin(phase) * radius * 0.3)
                performer.rotation = sin(phase * 1.7) * 22
                performer.scale = 1 + 0.1 * bounce
                performer.squash = 1 + 0.12 * (1 - bounce)
                performer.lift = bounce * 36
                assign(performer, isMine: isMine)
            }

        case .finale, .over:
            // Shoulder to shoulder, taking turns bouncing for the camera.
            let progress = progress(ReunionTuning.rompEnd, ReunionTuning.showEnd)
            let slide = min(progress / 0.14, 1)
            let eased = 1 - pow(1 - slide, 3)
            let time = elapsed - ReunionTuning.rompEnd
            for isMine in [true, false] {
                let side: Double = isMine ? -1 : 1
                let bounce = abs(sin(time * 5.4 + (isMine ? 0 : .pi / 2)))
                let target = CGPoint(x: centre.x + side * separation * 0.5, y: centre.y)
                let from = (isMine ? handOff?.mine : handOff?.theirs) ?? target
                var performer = Performer()
                performer.position = CGPoint(x: from.x + (target.x - from.x) * eased,
                                             y: from.y + (target.y - from.y) * eased)
                performer.rotation = sin(time * 5.4 + (isMine ? 0 : .pi / 2)) * 11
                performer.scale = 1 + 0.07 * bounce
                performer.squash = 1 + 0.1 * (1 - bounce)
                performer.lift = bounce * 28
                assign(performer, isMine: isMine)
            }
        }
    }

    private func assign(_ performer: Performer, isMine: Bool) {
        if isMine {
            mine = performer
        } else {
            theirs = performer
        }
    }

    // MARK: Particles

    private func updateParticles(_ step: TimeInterval) {
        guard !particles.isEmpty else { return }

        // Shells reaching the end of their fuse burst, but not while the array is being
        // walked, so the new sparks wait until the sweep is done.
        var bursts: [(point: CGPoint, hue: Double)] = []

        for index in particles.indices.reversed() {
            var particle = particles[index]
            particle.life -= step

            if particle.drag > 0 {
                let damping = exp(-particle.drag * step)
                particle.velocity.width *= damping
                particle.velocity.height *= damping
            }
            particle.velocity.height += particle.gravity * step
            particle.position.x += particle.velocity.width * step
            particle.position.y += particle.velocity.height * step
            particle.angle += particle.spin * step
            particle.size += particle.growth * step

            if particle.life <= 0 {
                if particle.burstsOnDeath {
                    bursts.append((particle.position, particle.hue))
                }
                particles.remove(at: index)
            } else {
                particles[index] = particle
            }
        }

        for burst in bursts {
            explode(at: burst.point, hue: burst.hue)
        }
    }

    /// The steady background of the show: dust while they run, fireworks and hearts once
    /// they are together.
    private func spawnAmbience(_ step: TimeInterval) {
        switch beat {
        case .charging:
            dust(behind: mine, towards: 1)
            dust(behind: theirs, towards: -1)

        case .romping, .finale:
            if elapsed >= nextFireworkAt {
                nextFireworkAt = elapsed + ReunionTuning.fireworkInterval
                launchFirework()
            }
            if elapsed >= nextCheerAt {
                nextCheerAt = elapsed + ReunionTuning.cheerInterval
                isFriendsTurn.toggle()
                onCue?(isFriendsTurn ? .friendCheer : .cheer)
            }
            // A drizzle of hearts rising out from between the two of them.
            if Double.random(in: 0...1) < step * 24 {
                add(Particle(
                    position: CGPoint(x: centre.x + Double.random(in: -70...70),
                                      y: centre.y + Double.random(in: -10...30)),
                    velocity: CGSize(width: Double.random(in: -50...50),
                                     height: Double.random(in: -150...(-80))),
                    life: 1.5, lifespan: 1.5,
                    size: Double.random(in: 20...34),
                    style: .glyph(Double.random(in: 0...1) < 0.6 ? .heart : ReunionGlyph.random),
                    gravity: 30, drag: 0.8
                ))
            }

        case .spotting, .colliding, .over:
            break
        }
    }

    /// Everything at once: the moment they actually hit each other.
    private func collide() {
        onCue?(.impact)
        flash = 1
        shake = 1
        ring(at: centre, size: 30, growth: 900, life: 0.5, width: 10)
        ring(at: centre, size: 14, growth: 540, life: 0.8, width: 4)
        sparks(at: centre, count: 56, speed: 200...780, hue: 0.06)
        glyphs(at: centre, count: 14, speed: 160...460)
        confetti(count: 70)
    }

    private func finale() {
        onCue?(.finale)
        flash = 0.8
        shake = 0.75
        confetti(count: 90)
        glyphs(at: centre, count: 10, speed: 140...380)
        for index in 0..<4 {
            launchFirework(extraFuse: Double(index) * 0.13)
        }
    }

    /// One shell, launched from below the bottom edge, timed to reach its apex exactly as
    /// the fuse runs out.
    private func launchFirework(extraFuse: Double = 0) {
        guard stage != .zero else { return }
        let floor = stage.height + 40
        let apex = Double.random(in: stage.height * 0.12...stage.height * 0.40)
        let fuse = Double.random(in: 0.5...0.75) + extraFuse

        add(Particle(
            position: CGPoint(x: Double.random(in: stage.width * 0.12...stage.width * 0.88), y: floor),
            velocity: CGSize(width: Double.random(in: -40...40), height: -(floor - apex) / fuse),
            life: fuse, lifespan: fuse, size: 8,
            style: .streak,
            hue: Double.random(in: 0...1),
            burstsOnDeath: true
        ))
    }

    private func explode(at point: CGPoint, hue: Double) {
        onCue?(.firework)
        flash = max(flash, 0.32)
        sparks(at: point, count: 34, speed: 110...430, hue: hue)
        glyphs(at: point, count: 4, speed: 80...230)
        ring(at: point, size: 10, growth: 400, life: 0.45, width: 3)
    }

    // MARK: Spawning

    private func sparks(at point: CGPoint, count: Int, speed: ClosedRange<Double>, hue: Double) {
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let velocity = Double.random(in: speed)
            let life = Double.random(in: 0.5...1.1)
            add(Particle(
                position: point,
                velocity: CGSize(width: cos(angle) * velocity, height: sin(angle) * velocity),
                life: life, lifespan: life,
                size: Double.random(in: 2.5...6),
                style: .spark,
                hue: (hue + Double.random(in: 0...0.14)).truncatingRemainder(dividingBy: 1),
                gravity: 210, drag: 1.5
            ))
        }
    }

    private func glyphs(at point: CGPoint, count: Int, speed: ClosedRange<Double>) {
        for _ in 0..<count {
            let angle = Double.random(in: 0...(2 * .pi))
            let velocity = Double.random(in: speed)
            let life = Double.random(in: 0.9...1.5)
            add(Particle(
                position: point,
                velocity: CGSize(width: cos(angle) * velocity, height: sin(angle) * velocity),
                life: life, lifespan: life,
                size: Double.random(in: 22...40),
                style: .glyph(ReunionGlyph.random),
                gravity: 90, drag: 1.1
            ))
        }
    }

    /// Paper thrown up from the bottom corners, on its way back down.
    private func confetti(count: Int) {
        guard stage != .zero else { return }
        for _ in 0..<count {
            let fromLeft = Bool.random()
            let life = Double.random(in: 1.6...2.6)
            add(Particle(
                position: CGPoint(x: fromLeft ? -20 : stage.width + 20,
                                  y: stage.height + Double.random(in: 0...60)),
                velocity: CGSize(width: Double.random(in: 180...520) * (fromLeft ? 1 : -1),
                                 height: Double.random(in: -900...(-520))),
                life: life, lifespan: life,
                size: Double.random(in: 9...17),
                style: .confetti,
                hue: Double.random(in: 0...1),
                angle: Double.random(in: 0...360),
                spin: Double.random(in: -420...420),
                gravity: 620, drag: 0.35
            ))
        }
    }

    private func ring(at point: CGPoint, size: Double, growth: Double,
                      life: TimeInterval, width: Double) {
        add(Particle(
            position: point, velocity: .zero,
            life: life, lifespan: life,
            size: size, style: .ring,
            growth: growth, lineWidth: width
        ))
    }

    /// Puffs kicked up behind a sprinting pet.
    private func dust(behind performer: Performer, towards direction: Double) {
        guard Double.random(in: 0...1) < 0.75 else { return }
        let life = Double.random(in: 0.25...0.5)
        add(Particle(
            position: CGPoint(x: performer.position.x - direction * 30,
                              y: performer.position.y + 44 - performer.lift),
            velocity: CGSize(width: -direction * Double.random(in: 120...320),
                             height: Double.random(in: -90...(-20))),
            life: life, lifespan: life,
            size: Double.random(in: 3...7),
            style: .streak,
            hue: 0.12,
            gravity: 240, drag: 2.2
        ))
    }

    private func add(_ particle: Particle) {
        if particles.count >= ReunionTuning.maximumParticles {
            particles.removeFirst()
        }
        particles.append(particle)
    }

    // MARK: Helpers

    private func progress(_ from: TimeInterval, _ to: TimeInterval) -> Double {
        guard to > from else { return 1 }
        return min(max((elapsed - from) / (to - from), 0), 1)
    }
}
