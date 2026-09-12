import Foundation
import SwiftUI

/// A short-lived symbol that floats up off the pet — hearts while petting, crumbs while
/// eating, and so on.
struct FloatingSymbol: Identifiable, Sendable {
    let id = UUID()
    let symbol: String
    let horizontal: Double
    let scale: Double
}

/// The single coordinator for the whole app: it owns the pet, runs the simulation clock,
/// and decides when to make a noise, buzz, complain or tell the neighbours.
@Observable
final class PetWorld {
    static let shared = PetWorld()

    // MARK: Observable state

    private(set) var pet: Pet?
    /// The speech bubble above the pet, cleared automatically after a few seconds.
    private(set) var speech: String?
    private(set) var isBeingPetted = false
    /// 0...1, how vigorously the finger is moving right now.
    private(set) var pettingIntensity: Double = 0
    private(set) var floatingSymbols: [FloatingSymbol] = []

    /// Mirrored in the UI with bindings; call `applyPreferences()` after changes.
    var preferences: Preferences

    let holdSensor = HoldSensor()
    let notifier = PetNotifier()
    let locator = PetLocator()
    let social = PetSocial()

    // MARK: Private state

    private var tickTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var hasStarted = false
    private var isForeground = true
    private var lastComplaintAt = Date.distantPast
    private var lastGreetedAt = Date.distantPast
    private var lastSavedAt = Date.distantPast
    private var lastHeartAt = Date.distantPast

    private init() {
        preferences = Preferences.load()
        pet = PetArchive.load()
        social.onMessage = { [weak self] card, message in
            self?.receive(message, from: card)
        }
        PetVoice.shared.isEnabled = preferences.soundEnabled
        PetVoice.shared.overridesSilentSwitch = preferences.overridesSilentSwitch
        PetHaptics.shared.isEnabled = preferences.hapticsEnabled
        notifier.isEnabled = preferences.notificationsEnabled
    }

    var hasPet: Bool { pet != nil }

    // MARK: Lifecycle

    func start() async {
        hasStarted = true
        notifier.registerCategories()
        await notifier.refreshAuthorization()
        PetHaptics.shared.prepare()
        PetVoice.shared.activate()
        holdSensor.start()
        runClock()
        startNearbyIfNeeded()
        greet()
    }

    func handleScenePhase(_ phase: ScenePhase) {
        switch phase {
        case .active:
            isForeground = true
            PetVoice.shared.activate()
            holdSensor.start()
            runClock()
            notifier.cancelAbandonmentNudge()
            startNearbyIfNeeded()
            Task { await notifier.refreshAuthorization() }
            greet()

        case .background:
            isForeground = false
            endPetting()
            PetVoice.shared.deactivate()
            PetHaptics.shared.stopPurr()
            holdSensor.stop()
            tickTask?.cancel()
            tickTask = nil
            social.stop()
            if let pet {
                PetArchive.save(pet)
                notifier.rescheduleNeglectLadder(for: pet)
                // The phone is out of sight; give it a few minutes before pouting.
                notifier.scheduleAbandonmentNudge(for: pet, after: 18 * 60)
            }

        case .inactive:
            isForeground = false
            PetHaptics.shared.stopPurr()

        @unknown default:
            break
        }
    }

    /// Pushes preference changes down into the audio, haptics and notification layers.
    func applyPreferences() {
        preferences.save()
        PetVoice.shared.isEnabled = preferences.soundEnabled
        PetVoice.shared.overridesSilentSwitch = preferences.overridesSilentSwitch
        PetHaptics.shared.isEnabled = preferences.hapticsEnabled
        notifier.isEnabled = preferences.notificationsEnabled

        if !preferences.soundEnabled { PetVoice.shared.stopComfortLoop() }
        if !preferences.hapticsEnabled { PetHaptics.shared.stopPurr() }
        if preferences.nearbyEnabled {
            startNearbyIfNeeded()
        } else {
            social.stop()
        }
        if let pet {
            if preferences.notificationsEnabled {
                notifier.rescheduleNeglectLadder(for: pet)
            } else {
                notifier.cancelEverything()
            }
        }
    }

    // MARK: Adoption and settings

    func adopt(name: String, kind: PetKind) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var newPet = Pet(name: trimmed.isEmpty ? kind.suggestedNames[0] : trimmed, kind: kind)
        if let coordinate = locator.coordinate {
            newPet.homeLatitude = coordinate.latitude
            newPet.homeLongitude = coordinate.longitude
        }
        pet = newPet
        PetArchive.save(newPet)
        notifier.rescheduleNeglectLadder(for: newPet)
        startNearbyIfNeeded()

        PetVoice.shared.play(newPet.voice.delighted, voice: newPet.voice)
        PetHaptics.shared.celebrate()
        emit("sparkles")
        say("\(newPet.name) has decided this phone is home.")
    }

    func rename(to name: String) {
        guard var current = pet else { return }
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        current.name = trimmed
        pet = current
        persist()
        say("Answers to \(trimmed) now.")
    }

    func changeKind(to kind: PetKind) {
        guard var current = pet, current.kind != kind else { return }
        current.kind = kind
        pet = current
        persist()
        PetVoice.shared.stopComfortLoop()
        PetVoice.shared.play(kind.voice.delighted, voice: kind.voice)
        say("\(current.name) is a \(kind.displayName.lowercased()) today.")
    }

    /// Marks the current spot as the den, so the pet can tell when you are home.
    func setHomeHere() {
        guard var current = pet, let coordinate = locator.coordinate else { return }
        current.homeLatitude = coordinate.latitude
        current.homeLongitude = coordinate.longitude
        pet = current
        persist()
        say("Den set. \(current.name) will know when you're back.")
    }

    func releasePet() {
        endPetting()
        social.stop()
        notifier.cancelEverything()
        PetVoice.shared.stopComfortLoop()
        PetArchive.erase()
        pet = nil
        speech = nil
    }

    // MARK: Care

    func beginPetting() {
        guard let pet, isForeground else { return }
        isBeingPetted = true
        notifier.cancelAbandonmentNudge()
        PetVoice.shared.startComfortLoop(pet.voice.comfort, voice: pet.voice, volume: 0.8)
        PetHaptics.shared.startPurr(intensity: 0.45 + 0.35 * pet.moodScore)
        say(Self.pettingLine(for: pet))
    }

    /// `speed` is the finger's movement this frame, in points.
    func continuePetting(speed: Double) {
        guard isBeingPetted, let pet else { return }
        pettingIntensity = min(max(speed / 40, 0), 1)
        PetHaptics.shared.startPurr(intensity: 0.4 + 0.5 * pettingIntensity)

        // Hearts, but not a blizzard of them.
        if Date.now.timeIntervalSince(lastHeartAt) > 0.45, pettingIntensity > 0.25 {
            lastHeartAt = .now
            emit(pet.needs.affection > 0.9 ? "heart.fill" : "heart")
        }
    }

    func endPetting() {
        guard isBeingPetted else { return }
        isBeingPetted = false
        pettingIntensity = 0
        PetVoice.shared.stopComfortLoop()
        PetHaptics.shared.stopPurr()

        guard var current = pet else { return }
        current.recordCare(bond: 1.5)
        pet = current
        afterCare()
    }

    func feed() {
        guard var current = pet else { return }
        if current.needs.fullness > 0.95 {
            PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.6)
            say("\(current.name) could not manage another bite. Genuinely.")
            return
        }
        current.needs.fullness += PetRules.fullnessPerMeal
        current.needs.fun += 0.04
        current.needs.clamp()
        current.recordCare(bond: 4)
        pet = current

        PetVoice.shared.play(current.voice.eating, voice: current.voice)
        PetHaptics.shared.tap(intensity: 0.65, sharpness: 0.75)
        emit("fork.knife")
        say("\(current.name) demolishes \(current.kind.favouriteFood).")
        afterCare()
    }

    func playTogether() {
        guard var current = pet else { return }
        if current.needs.rest < 0.16 {
            PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.6)
            emit("moon.zzz.fill")
            say("\(current.name) is too tired to play. Put the phone down for a bit.")
            return
        }
        current.needs.fun += PetRules.funPerPlaySession
        current.needs.rest -= PetRules.restCostPerPlaySession
        current.needs.fullness -= PetRules.fullnessCostPerPlaySession
        current.needs.clamp()
        current.recordCare(bond: 5)
        pet = current

        PetVoice.shared.play(current.voice.playing, voice: current.voice)
        PetHaptics.shared.celebrate()
        emit("tennisball.fill")
        say(Self.playLine(for: current))
        afterCare()
    }

    /// Used by the "Pet them" notification action, where there is no finger on screen yet.
    func quickCuddle() {
        guard var current = pet else { return }
        current.needs.affection += 0.2
        current.needs.clamp()
        current.recordCare(bond: 2)
        pet = current

        PetVoice.shared.play(current.voice.comfort, voice: current.voice, volume: 0.8)
        PetHaptics.shared.startPurr(intensity: 0.55)
        emit("heart.fill")
        say("\(current.name) melts into your hand.")
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2.5))
            PetHaptics.shared.stopPurr()
            _ = self
        }
        afterCare()
    }

    func handleNotificationAction(_ identifier: String) {
        switch identifier {
        case PetNotifier.Action.feed.rawValue:
            feed()
        case PetNotifier.Action.pet.rawValue:
            quickCuddle()
        default:
            greet()
        }
    }

    // MARK: Nearby pets

    var petCard: PetCard? {
        guard let pet else { return nil }
        return PetCard(
            id: pet.id.uuidString,
            name: pet.name,
            kind: pet.kind,
            level: pet.level,
            moodLabel: pet.mood.label,
            headline: Self.headline(for: pet)
        )
    }

    func nuzzle(_ card: PetCard) {
        guard var current = pet else { return }
        social.send(.nuzzle, to: card)
        social.note("\(current.name) nuzzled \(card.name).", symbolName: "heart.fill")
        current.needs.affection += 0.05
        current.needs.clamp()
        current.recordCare(bond: 1)
        pet = current
        PetHaptics.shared.tap(intensity: 0.5, sharpness: 0.2)
        afterCare()
    }

    func sendTreat(to card: PetCard) {
        guard var current = pet else { return }
        social.send(.treat, to: card)
        social.note("\(current.name) shared a snack with \(card.name).", symbolName: "gift.fill")
        current.needs.fullness -= 0.04
        current.needs.fun += 0.05
        current.needs.clamp()
        current.recordCare(bond: 1)
        pet = current
        emit("gift.fill")
        afterCare()
    }

    func invitePlay(_ card: PetCard) {
        guard let current = pet else { return }
        social.send(.playInvite, to: card)
        social.note("\(current.name) asked \(card.name) to play.", symbolName: "tennisball.fill")
        PetVoice.shared.play(current.voice.playing, voice: current.voice, volume: 0.7)
    }

    private func receive(_ message: PetMessage, from card: PetCard) {
        guard var current = pet else { return }

        switch message {
        case .hello:
            current.remember(friend: card)
            current.needs.fun += 0.06
            current.needs.affection += 0.03
            PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.7)
            PetHaptics.shared.celebrate()
            emit(card.kind.symbolName)
            say("\(current.name) is sniffing \(card.name) the \(card.kind.displayName.lowercased()).")

        case .nuzzle:
            current.needs.affection += 0.09
            social.note("\(card.name) nuzzled \(current.name).", symbolName: "heart.fill")
            PetVoice.shared.play(current.voice.comfort, voice: current.voice, volume: 0.6)
            emit("heart.fill")
            say("\(card.name) gave \(current.name) a nuzzle.")

        case .treat:
            current.needs.fullness += 0.12
            social.note("\(card.name) shared a snack with \(current.name).", symbolName: "gift.fill")
            PetVoice.shared.play(current.voice.eating, voice: current.voice, volume: 0.7)
            emit("gift.fill")
            say("\(card.name) brought \(current.name) a snack.")

        case .playInvite:
            current.needs.fun += 0.1
            current.needs.rest -= 0.03
            social.note("\(card.name) wants to play with \(current.name)!", symbolName: "tennisball.fill")
            social.send(.playAccept, to: card)
            PetVoice.shared.play(current.voice.playing, voice: current.voice, volume: 0.8)
            say("\(card.name) wants to play!")

        case .playAccept:
            current.needs.fun += 0.14
            current.needs.rest -= 0.05
            social.note("\(current.name) and \(card.name) had a proper romp.", symbolName: "sparkles")
            PetHaptics.shared.celebrate()
            emit("sparkles")
            say("\(current.name) and \(card.name) are playing.")
        }

        current.needs.clamp()
        current.recordCare(bond: 2)
        pet = current
        afterCare()
    }

    private func startNearbyIfNeeded() {
        guard hasStarted, preferences.nearbyEnabled, let petCard else {
            social.stop()
            return
        }
        social.start(as: petCard)
    }

    // MARK: Simulation clock

    private func runClock() {
        guard tickTask == nil || tickTask?.isCancelled == true else { return }
        tickTask?.cancel()
        tickTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(500))
                guard let self, !Task.isCancelled else { return }
                self.tick()
            }
        }
    }

    private func tick() {
        guard var current = pet else { return }
        let now = Date.now
        let step = 0.5

        current.advance(to: now)

        if isBeingPetted {
            current.needs.affection += PetRules.affectionPerSecondOfPetting * step
            current.needs.rest -= PetRules.restCostPerSecondOfPetting * step
            current.recordCare(bond: 0.02, now: now)
        } else if holdSensor.isHeld {
            current.needs.affection += PetRules.affectionPerSecondHeld * step
            current.needs.fun += PetRules.funPerSecondHeld * step
        } else if holdSensor.isSetDown {
            current.needs.rest += PetRules.restRecoveryPerSecondAsleep * step
        }

        // The first fix of the session becomes home, if the pet hasn't got one.
        if current.homeLatitude == nil, let coordinate = locator.coordinate {
            current.homeLatitude = coordinate.latitude
            current.homeLongitude = coordinate.longitude
        }

        current.needs.clamp()
        pet = current

        updateComfortLoop()
        complainIfAbandoned()
        autosave(now)
    }

    private func updateComfortLoop() {
        guard let pet, isForeground else { return }
        if isBeingPetted {
            PetVoice.shared.startComfortLoop(pet.voice.comfort, voice: pet.voice,
                                             volume: Float(0.6 + 0.3 * pet.moodScore))
        } else if PetVoice.shared.isPurring {
            PetVoice.shared.stopComfortLoop()
        }
    }

    /// The pet noticing, out loud, that it has been abandoned on a table.
    private func complainIfAbandoned() {
        guard let pet, isForeground, !isBeingPetted else { return }
        guard holdSensor.hasBeenAbandoned else { return }
        guard Date.now.timeIntervalSince(lastComplaintAt) > PetRules.complaintCooldown else { return }
        lastComplaintAt = .now

        PetVoice.shared.play(pet.voice.lonely, voice: pet.voice, volume: 1.0)
        PetHaptics.shared.tap(intensity: 0.9, sharpness: 0.8)
        emit("exclamationmark.bubble.fill")
        say(Self.setDownLine(for: pet))
        notifier.scheduleAbandonmentNudge(for: pet, after: 10 * 60)
    }

    private func greet() {
        guard let pet, Date.now.timeIntervalSince(lastGreetedAt) > 25 else { return }
        lastGreetedAt = .now
        let happy = pet.moodScore > 0.6
        PetVoice.shared.play(happy ? pet.voice.delighted : pet.voice.lonely, voice: pet.voice)
        emit(happy ? "sparkles" : "heart")
        say(Self.greetingLine(for: pet))
    }

    private func afterCare() {
        persist()
        if let pet {
            notifier.rescheduleNeglectLadder(for: pet)
        }
        if let petCard, social.isRunning {
            social.announce(petCard)
        }
    }

    private func persist() {
        guard let pet else { return }
        lastSavedAt = .now
        PetArchive.save(pet)
    }

    private func autosave(_ now: Date) {
        guard let pet, now.timeIntervalSince(lastSavedAt) > 20 else { return }
        lastSavedAt = now
        PetArchive.save(pet)
    }

    // MARK: Chatter

    func say(_ text: String) {
        speech = text
        speechTask?.cancel()
        speechTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(5))
            guard let self, !Task.isCancelled else { return }
            self.speech = nil
        }
    }

    func emit(_ symbol: String) {
        let item = FloatingSymbol(symbol: symbol,
                                  horizontal: Double.random(in: -1...1),
                                  scale: Double.random(in: 0.75...1.3))
        floatingSymbols.append(item)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(1.7))
            self?.floatingSymbols.removeAll { $0.id == item.id }
        }
    }

    /// The one-line summary shown under the pet.
    var statusLine: String {
        guard let pet else { return "" }
        if isBeingPetted {
            return pet.kind.canPurr ? "Purring." : "Making an extremely happy noise."
        }
        if holdSensor.isFaceDown {
            return "Face down on a table. \(pet.name) has noticed."
        }
        if holdSensor.isSetDown {
            return "Put down \(Self.relative(holdSensor.setDownDuration)) ago."
        }
        if holdSensor.isHeld {
            return "Happy to be held."
        }
        if let need = pet.neediest {
            return Self.wish(for: need, pet: pet)
        }
        return "\(pet.mood.label). Not a single complaint."
    }

    static func wish(for need: NeedKind, pet: Pet) -> String {
        switch need {
        case .affection: "Wants your hands on the screen."
        case .fun: "Bored. Suggests a game."
        case .fullness: "Would like \(pet.kind.favouriteFood)."
        case .rest: "Sleepy. A quiet moment in a pocket would help."
        }
    }

    private static func headline(for pet: Pet) -> String {
        "Level \(pet.level) · \(pet.levelTitle) · \(pet.mood.label)"
    }

    private static func relative(_ seconds: TimeInterval) -> String {
        let minutes = Int(seconds / 60)
        if minutes < 1 { return "a moment" }
        if minutes == 1 { return "a minute" }
        if minutes < 60 { return "\(minutes) minutes" }
        let hours = minutes / 60
        return hours == 1 ? "an hour" : "\(hours) hours"
    }

    private static func pettingLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name) leans into it, eyes shut."
        case .dog: "\(pet.name)'s whole body is wagging."
        case .bunny: "\(pet.name) has flopped over. That's a compliment."
        case .dragon: "\(pet.name) rumbles like a small furnace."
        }
    }

    private static func playLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name) ambushes your thumb."
        case .dog: "\(pet.name) brings the ball back. Twice."
        case .bunny: "\(pet.name) binkies across the screen."
        case .dragon: "\(pet.name) chases a spark round the glass."
        }
    }

    private static func setDownLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name): \"…you're just going to leave me here?\""
        case .dog: "\(pet.name) barks. You are being called back."
        case .bunny: "\(pet.name) thumps a foot at you."
        case .dragon: "\(pet.name) roars quietly at the ceiling."
        }
    }

    private static func greetingLine(for pet: Pet) -> String {
        if pet.moodScore > 0.8 {
            return "\(pet.name) is thrilled you're back."
        }
        if pet.moodScore > 0.5 {
            return "\(pet.name) looks up at you."
        }
        if let need = pet.neediest {
            return wish(for: need, pet: pet)
        }
        return "\(pet.name) has been waiting."
    }
}
