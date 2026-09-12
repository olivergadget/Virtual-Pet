import Foundation
#if os(iOS)
import CoreMotion
#endif

/// Works out whether the phone is in a hand or abandoned on a table.
///
/// This is the mechanic that makes the pet live in the *device* rather than in an app:
/// holding the phone is itself an act of care, and setting it down is noticed.
@Observable
final class HoldSensor {
    /// True while the phone is being carried, tilted or fidgeted with.
    private(set) var isHeld = true
    /// True once the phone has been lying flat and motionless.
    private(set) var isSetDown = false
    /// True when the phone is face down — the pet reads this as being ignored on purpose.
    private(set) var isFaceDown = false
    /// Smoothed movement: roughly 0 on a table, 1 when waved around.
    private(set) var movement: Double = 0
    /// When the current stretch of stillness began, if any.
    private(set) var setDownSince: Date?

    var setDownDuration: TimeInterval {
        guard let setDownSince else { return 0 }
        return Date.now.timeIntervalSince(setDownSince)
    }

    /// True once the phone has been ignored long enough for the pet to complain.
    var hasBeenAbandoned: Bool {
        isSetDown && setDownDuration > PetRules.setDownGracePeriod
    }

    #if os(iOS)
    private let manager = CMMotionManager()
    private var energy = 0.0
    private var lastMovedAt = Date.now
    #endif

    func start() {
        #if os(iOS)
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 15.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] data, _ in
            guard let self, let data else { return }
            self.ingest(data)
        }
        #endif
    }

    func stop() {
        #if os(iOS)
        guard manager.isDeviceMotionActive else { return }
        manager.stopDeviceMotionUpdates()
        #endif
    }

    #if os(iOS)
    private func ingest(_ data: CMDeviceMotion) {
        let acceleration = (data.userAcceleration.x * data.userAcceleration.x
            + data.userAcceleration.y * data.userAcceleration.y
            + data.userAcceleration.z * data.userAcceleration.z).squareRoot()
        let rotation = (data.rotationRate.x * data.rotationRate.x
            + data.rotationRate.y * data.rotationRate.y
            + data.rotationRate.z * data.rotationRate.z).squareRoot()

        // A hand is never perfectly still, so a low-passed reading separates
        // "resting in a palm" from "lying on a worktop" surprisingly well.
        energy = energy * 0.82 + (acceleration + rotation * 0.08) * 0.18
        movement = min(energy * 6, 1)

        let now = Date.now
        if energy > 0.022 {
            lastMovedAt = now
        }
        isHeld = now.timeIntervalSince(lastMovedAt) < 3.5

        // Gravity points along -z when the screen faces up, +z when it faces down.
        isFaceDown = data.gravity.z > 0.82
        let restingFlat = abs(data.gravity.z) > 0.80 && !isHeld

        if restingFlat {
            if setDownSince == nil { setDownSince = now }
        } else {
            setDownSince = nil
        }
        isSetDown = restingFlat
    }
    #endif
}
