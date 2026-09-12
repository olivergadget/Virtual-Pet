import Foundation
#if os(iOS)
import CoreHaptics
import UIKit
#endif

/// The physical half of a purr. Sound alone is not convincing — the rumble under your
/// fingers is what sells the illusion that something alive is in your hand.
@MainActor
final class PetHaptics {
    static let shared = PetHaptics()

    var isEnabled = true

    #if os(iOS)
    private var engine: CHHapticEngine?
    private var purrPlayer: CHHapticAdvancedPatternPlayer?
    private var isPurring = false

    private var supportsHaptics: Bool {
        CHHapticEngine.capabilitiesForHardware().supportsHaptics
    }
    #endif

    private init() {}

    func prepare() {
        #if os(iOS)
        guard isEnabled, supportsHaptics, engine == nil else { return }
        engine = try? CHHapticEngine()
        engine?.playsHapticsOnly = true
        engine?.isAutoShutdownEnabled = true
        try? engine?.start()
        #endif
    }

    /// A looping rumble whose intensity you can nudge as the pet gets happier.
    func startPurr(intensity: Double = 0.6) {
        #if os(iOS)
        guard isEnabled, supportsHaptics else { return }
        prepare()
        guard let engine else { return }
        try? engine.start()

        if isPurring {
            try? purrPlayer?.sendParameters(
                [CHHapticDynamicParameter(parameterID: .hapticIntensityControl,
                                          value: Float(intensity),
                                          relativeTime: 0)],
                atTime: CHHapticTimeImmediate
            )
            return
        }

        let event = CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.08)
            ],
            relativeTime: 0,
            duration: 1.2
        )
        // The curve is what makes it breathe rather than buzz.
        let curve = CHHapticParameterCurve(
            parameterID: .hapticIntensityControl,
            controlPoints: [
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.0, value: 0.55),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.3, value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.6, value: 0.6),
                CHHapticParameterCurve.ControlPoint(relativeTime: 0.9, value: 1.0),
                CHHapticParameterCurve.ControlPoint(relativeTime: 1.2, value: 0.55)
            ],
            relativeTime: 0
        )

        guard let pattern = try? CHHapticPattern(events: [event], parameterCurves: [curve]),
              let player = try? engine.makeAdvancedPlayer(with: pattern)
        else { return }

        player.loopEnabled = true
        try? player.start(atTime: CHHapticTimeImmediate)
        purrPlayer = player
        isPurring = true
        #endif
    }

    func stopPurr() {
        #if os(iOS)
        guard isPurring else { return }
        try? purrPlayer?.stop(atTime: CHHapticTimeImmediate)
        purrPlayer = nil
        isPurring = false
        #endif
    }

    /// A single beat — a paw tap, a nose boop, a bite of food.
    func tap(intensity: Double = 0.7, sharpness: Double = 0.4) {
        #if os(iOS)
        guard isEnabled else { return }
        guard supportsHaptics else {
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            return
        }
        prepare()
        guard let engine else { return }
        try? engine.start()

        let event = CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: Float(intensity)),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: Float(sharpness))
            ],
            relativeTime: 0
        )
        guard let pattern = try? CHHapticPattern(events: [event], parameters: []),
              let player = try? engine.makePlayer(with: pattern)
        else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
        #endif
    }

    /// Three quick beats: used when the pet is delighted or meets a friend.
    func celebrate() {
        #if os(iOS)
        guard isEnabled else { return }
        guard supportsHaptics else {
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            return
        }
        prepare()
        guard let engine else { return }
        try? engine.start()

        let events = [0.0, 0.09, 0.2].enumerated().map { index, time in
            CHHapticEvent(
                eventType: .hapticTransient,
                parameters: [
                    CHHapticEventParameter(parameterID: .hapticIntensity,
                                           value: Float(0.6 + Double(index) * 0.15)),
                    CHHapticEventParameter(parameterID: .hapticSharpness, value: 0.55)
                ],
                relativeTime: time
            )
        }
        guard let pattern = try? CHHapticPattern(events: events, parameters: []),
              let player = try? engine.makePlayer(with: pattern)
        else { return }
        try? player.start(atTime: CHHapticTimeImmediate)
        #endif
    }
}
