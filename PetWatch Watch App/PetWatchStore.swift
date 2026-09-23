import Foundation
import SwiftUI
import WidgetKit
import WatchKit

/// The watch's whole model layer.
///
/// The watch is a window, not a second home: the phone runs the simulation and owns the
/// pet, and everything here is either the last pet the phone sent or a small local
/// estimate of what has happened since. Care taps go to the phone as errands and come
/// back as a whole new pet.
///
/// The pet is also written to the watch's own App Group container on arrival, which is
/// what the complication reads and what makes the app show something on a wrist that
/// hasn't seen a phone all morning.
@Observable
final class PetWatchStore {
    static let shared = PetWatchStore()

    /// The pet as far as the watch knows. `nil` until a phone has sent one.
    private(set) var pet: Pet?

    /// A line of confirmation after a tap, cleared after a few seconds. The watch has no
    /// room for the phone's speech bubbles, so this is the whole of its chatter.
    private(set) var note: String?

    /// True while an errand is in the air and the phone hasn't answered yet.
    private(set) var isWaitingOnPhone = false

    private let sync = PetSync.shared
    private var tickTask: Task<Void, Never>?
    private var noteTask: Task<Void, Never>?
    private var waitTask: Task<Void, Never>?

    /// True when the phone is awake and listening. Taps still work when it isn't — they
    /// are queued — so this only changes how quickly an answer comes back.
    var isPhoneReachable: Bool { sync.isReachable }

    /// False when there is no phone with the app on it. Nothing here works without one.
    var hasPhone: Bool { sync.hasCounterpart }

    private init() {
        // Whatever the phone last sent, from before the app was closed.
        pet = PetArchive.load()
        sync.onPet = { [weak self] pet in
            self?.accept(pet)
        }
        sync.onRelease = { [weak self] in
            self?.forget()
        }
    }

    // MARK: Lifecycle

    func start() {
        sync.activate()
        runClock()
    }

    func stop() {
        tickTask?.cancel()
        tickTask = nil
        if let pet { PetArchive.save(pet) }
    }

    /// A pet has arrived from the phone. This is the authority, so it replaces whatever
    /// the watch had been guessing — including any optimistic change from a recent tap.
    private func accept(_ pet: Pet) {
        self.pet = pet
        isWaitingOnPhone = false
        waitTask?.cancel()
        // Saving reloads the complication as a side effect, so the watch face catches up
        // at the same moment the app does.
        PetArchive.save(pet)
    }

    /// The pet has been let go on the phone. Nothing here is worth keeping, including the
    /// cached copy the complication reads.
    private func forget() {
        pet = nil
        note = nil
        isWaitingOnPhone = false
        waitTask?.cancel()
        PetArchive.erase()
    }

    /// Needs drift whether or not a phone is in range, so the watch runs the app's own
    /// simulation forward between syncs. A minute is plenty: nothing here moves fast, and
    /// the wrist is not the place to spend battery on a 2 Hz clock.
    private func runClock() {
        guard tickTask == nil else { return }
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                guard let self else { return }
                if var current = self.pet {
                    current.advance(to: .now)
                    self.pet = current
                }
                try? await Task.sleep(for: .seconds(60))
            }
        }
    }

    // MARK: Care

    /// True when there is room in the pet for another bowlful.
    var canFeed: Bool { (pet?.needs.fullness ?? 1) <= PetRules.maximumFullnessToEat }

    func feed() {
        guard var current = pet else { return }
        guard canFeed else {
            tap(.failure)
            say("\(current.name) couldn't manage another bite.")
            return
        }

        // Guessed locally so the meters move under the finger. The phone applies the same
        // rules and sends back the real pet, which overwrites this.
        current.needs.fullness += PetRules.fullnessPerMeal
        current.needs.fun += 0.04
        current.needs.clamp()
        current.recordCare(bond: 4)
        pet = current

        send(.feed)
        tap(.success)
        say("Fed \(current.name) \(current.kind.favouriteFood).")
    }

    func cuddle() {
        guard var current = pet else { return }
        current.needs.affection += 0.2
        current.needs.clamp()
        current.recordCare(bond: 2)
        pet = current

        send(.cuddle)
        tap(.success)
        say("\(current.name) melts into your hand.")
    }

    /// Asks the pet to do a trick it already knows. Whether it actually manages is the
    /// phone's roll of the dice, not the watch's, so nothing is guessed here.
    func perform(_ trick: TrickKind) {
        guard let current = pet, current.knows(trick) else { return }
        send(.perform(trick))
        tap(.click)
        say("\(current.name): \(trick.cue)")
    }

    private func send(_ errand: PetErrand) {
        sync.send(errand)
        guard sync.hasCounterpart else { return }
        // Only worth showing a wait when there is a chance of a quick answer. An errand
        // queued for a sleeping phone may not be picked up for a good while.
        guard sync.isReachable else { return }
        isWaitingOnPhone = true
        waitTask?.cancel()
        waitTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            self.isWaitingOnPhone = false
        }
    }

    // MARK: Feedback

    private func say(_ text: String) {
        note = text
        noteTask?.cancel()
        noteTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard let self, !Task.isCancelled else { return }
            self.note = nil
        }
    }

    private func tap(_ kind: WKHapticType) {
        WKInterfaceDevice.current().play(kind)
    }
}
