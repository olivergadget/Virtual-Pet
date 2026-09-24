import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

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

    /// The trick being shown off right now, how far through the routine it is, and
    /// whether it is going well, so whichever screen is drawing the pet can pose it.
    private(set) var showOff: TrickKind?
    private(set) var showOffRoutine: Double = 0
    private(set) var showOffSucceeded = true

    /// Set when a friend turns up and the reunion show should take over the screen.
    private(set) var reunion: ReunionCast?
    /// True while a meal, game, cuddle or lesson has the screen, so a reunion waits its
    /// turn rather than fighting another full-screen cover for it.
    private(set) var isBusyWithSession = false

    /// Mirrored in the UI with bindings; call `applyPreferences()` after changes.
    var preferences: Preferences

    let holdSensor = HoldSensor()
    /// The person the pet belongs to. Nothing in the app is reachable until they have
    /// signed in, and a pet stops reaching out the moment they sign out.
    let owner = PetOwner()
    let notifier = PetNotifier()
    let locator = PetLocator()
    let social = PetSocial()
    let postcards = PetFeed()
    /// The pet on the wrist, if there is a watch. The phone stays the only place the
    /// simulation runs: the watch is sent whole pets and sends back small errands.
    let watch = PetSync.shared
    let groups = PetGroups()

    // MARK: Private state

    private var tickTask: Task<Void, Never>?
    private var speechTask: Task<Void, Never>?
    private var showOffTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var hasStarted = false
    private var isForeground = true
    /// A reunion that arrived while something else had the screen.
    private var queuedReunion: ReunionCast?
    /// When each friend last got the full reunion treatment, keyed by pet id.
    private var lastReunionAt: [String: Date] = [:]
    /// The last time the pet interrupted of its own accord. One gate for greetings,
    /// complaints and requests alike — see `PetRules.promptInterval`.
    private var lastPromptAt = Date.distantPast
    private var lastSavedAt = Date.distantPast
    private var lastHeartAt = Date.distantPast
    private var lastPourTapAt = Date.distantPast
    private var lastMunchAt = Date.distantPast
    private var lastSpillAt = Date.distantPast

    private init() {
        preferences = Preferences.load()
        pet = PetArchive.load()
        social.onMessage = { [weak self] card, message in
            self?.receive(message, from: card)
        }
        social.onArrival = { [weak self] card in
            guard let self else { return }
            self.stageReunion(with: card)
            // Somebody who has just walked in gets brought up to date: the groups you
            // share with them, then a few recent postcards they're entitled to.
            self.groups.shareGroups(with: card, myID: self.myPetID ?? "")
            if self.preferences.postcardsEnabled {
                self.postcards.sharePostcards(with: card, from: self.pet)
                // Anything we liked while they were away, so their postcards catch up
                // with the applause they have already had.
                self.postcards.shareLikes(with: card, from: self.pet)
            }
        }
        social.onPostcard = { [weak self] card, envelope in
            self?.receivePostcard(envelope, from: card)
        }
        social.onLike = { [weak self] card, message in
            self?.receiveLike(message, from: card)
        }
        social.onGroupMessage = { [weak self] card, message in
            self?.receiveGroupMessage(message, from: card)
        }

        // The feed knows nothing about Bonjour; this is the whole of its way out.
        postcards.send = { [weak self] message, card in
            guard let self, self.preferences.postcardsEnabled else { return }
            self.social.send(message, to: card)
        }
        postcards.nearby = { [weak self] in self?.social.nearby ?? [] }
        // The two policy questions the feed can't answer on its own. Both come down to
        // the same thing: a group postcard stays inside its group.
        postcards.canSend = { [weak self] post, card in
            guard let self else { return false }
            guard let groupID = post.groupID else { return true }
            return self.groups.group(id: groupID)?.contains(card.id) == true
        }
        postcards.accepts = { [weak self] post, card in
            guard let self else { return false }
            guard let groupID = post.groupID else { return true }
            return self.groups.allowsPost(inGroup: groupID, from: card.id, myID: self.myPetID ?? "")
        }

        groups.send = { [weak self] message, card in
            self?.social.send(message, to: card)
        }
        groups.nearby = { [weak self] in self?.social.nearby ?? [] }
        groups.onJoined = { [weak self] group in
            self?.celebrateJoining(group)
        }

        // The watch can only ask; the phone decides and answers with a whole pet.
        watch.onErrand = { [weak self] errand in
            self?.runErrand(errand)
        }
        watch.currentPet = { [weak self] in self?.pet }

        owner.onChange = { [weak self] in
            self?.ownerDidChange()
        }
        PetVoice.shared.isEnabled = preferences.soundEnabled
        PetVoice.shared.overridesSilentSwitch = preferences.overridesSilentSwitch
        PetHaptics.shared.isEnabled = preferences.hapticsEnabled
        refreshNotifierEnablement()
    }

    var hasPet: Bool { pet != nil }

    /// The pet's id as it travels between phones, which is how a member is identified in
    /// every group roster.
    var myPetID: String? { pet?.id.uuidString }

    // MARK: Lifecycle

    func start() async {
        hasStarted = true
        postcards.load()
        groups.load()
        notifier.registerCategories()
        await notifier.refreshAuthorization()
        PetHaptics.shared.prepare()
        PetVoice.shared.activate()
        holdSensor.start()
        runClock()
        startNearbyIfNeeded()
        // Sends the pet over as soon as the session is up — see `PetSync.currentPet`.
        watch.activate()
        // The icon can be out of step with the pet after a restore or a reinstall.
        PetAppIcon.apply(for: pet)
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
            watch.activate()
            Task { await notifier.refreshAuthorization() }
            // Access can be withdrawn from Settings while the app is in the background,
            // and coming back to the foreground is the first chance to notice.
            Task { await owner.refresh() }
            greet()

        case .background:
            isForeground = false
            endPetting()
            PetVoice.shared.deactivate()
            PetHaptics.shared.stopPurr()
            holdSensor.stop()
            tickTask?.cancel()
            tickTask = nil
            endShowOff()
            social.stop()
            // Nobody is watching, so a show that never got its turn is dropped rather
            // than sprung on the person when they come back.
            queuedReunion = nil
            if let pet {
                PetArchive.save(pet)
                // The watch is about to be the only one of the two that's awake, so it
                // gets the final word on where the pet stood.
                watch.share(pet, force: true)
                notifier.rescheduleNeglectLadder(for: pet)
                // The phone is out of sight; give it a quarter of an hour before pouting.
                notifier.scheduleAbandonmentNudge(for: pet, after: PetRules.promptInterval)
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
        refreshNotifierEnablement()

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

    // MARK: The owner

    /// The gate opened or closed. Logging out costs nothing: the pet, its bond, its
    /// friends, its tricks and every postcard are written to disk and picked up again on
    /// the way back in. What does stop is the pet reaching out — no nudges, and nothing
    /// on the local network under a name that has no owner behind it.
    private func ownerDidChange() {
        refreshNotifierEnablement()
        if owner.isSignedIn {
            startNearbyIfNeeded()
            if let pet {
                notifier.rescheduleNeglectLadder(for: pet)
                // Back on the wrist, from the phone's copy — which is the only one that
                // was ever authoritative.
                watch.share(pet, force: true)
            }
        } else {
            endPetting()
            // Written out before anything else, and not on the usual short delay: a pet
            // about to go behind the gate should be on disk to the second.
            persist()
            social.stop()
            notifier.cancelEverything()
            PetVoice.shared.stopComfortLoop()
            // The watch has no gate of its own, so a pet left on the wrist would walk
            // straight around this one. Its copy is only ever a mirror of the phone's,
            // and it comes back the moment somebody logs in again.
            watch.shareRelease()
        }
    }

    /// The notifier's one switch, which every scheduling path checks before it puts
    /// anything in the queue. Kept in one place so a nudge can't slip out on a later tick
    /// while the pet is sitting behind the sign-in screen.
    private func refreshNotifierEnablement() {
        notifier.isEnabled = owner.isSignedIn && preferences.notificationsEnabled
    }

    // MARK: Adoption and settings

    func adopt(name: String, kind: PetKind, appearance: PetAppearance = PetAppearance()) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        var newPet = Pet(
            name: trimmed.isEmpty ? kind.suggestedNames[0] : trimmed,
            kind: kind,
            appearance: appearance
        )
        if let coordinate = locator.coordinate {
            newPet.homeLatitude = coordinate.latitude
            newPet.homeLongitude = coordinate.longitude
        }
        pet = newPet
        PetArchive.save(newPet)
        // A brand new pet should be on the wrist before the person has put the phone down.
        watch.share(newPet, force: true)
        notifier.rescheduleNeglectLadder(for: newPet)
        startNearbyIfNeeded()
        PetAppIcon.apply(for: newPet)

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
        PetAppIcon.apply(for: current)
        PetVoice.shared.stopComfortLoop()
        PetVoice.shared.play(kind.voice.delighted, voice: kind.voice)
        say("\(current.name) is a \(kind.displayName.lowercased()) today.")
    }

    /// Colours and size from the designer. Saved on a short delay because a colour picker
    /// reports every frame of a drag, and none of those are worth a trip to disk.
    func updateAppearance(_ appearance: PetAppearance) {
        guard var current = pet, current.appearance != appearance else { return }
        current.appearance = appearance
        pet = current
        scheduleSave()
    }

    /// The hours the pet keeps, mirrored in the settings screen with a binding. Writing
    /// to it is the whole of the way the schedule changes.
    var schedule: PetSchedule {
        get { pet?.schedule ?? PetSchedule() }
        set { updateSchedule(newValue) }
    }

    /// The pet's own day. Saved on a short delay, because a time picker reports every
    /// minute the wheel passes through and the neglect ladder is rebuilt from this.
    func updateSchedule(_ schedule: PetSchedule) {
        guard var current = pet, current.schedule != schedule else { return }
        current.schedule = schedule
        pet = current
        scheduleSave(thenRescheduleNudges: true)
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
        // The postcards and the group memberships were theirs, photos and all.
        postcards.erase()
        groups.erase()
        pet = nil
        speech = nil
        // Otherwise the watch is left looking after a pet that no longer exists.
        watch.shareRelease()
        // Back to the paw print until someone adopts again.
        PetAppIcon.apply(for: nil)
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

    /// The instant meal behind the "Feed them" notification action, where there is no
    /// chance to pour a bowl. The Feed button opens a feeding session instead.
    func feed() {
        guard var current = pet else { return }
        if current.needs.fullness > PetRules.maximumFullnessToEat {
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

    // MARK: Meals

    /// True when there is room in the pet for another bowlful.
    var canEat: Bool { (pet?.needs.fullness ?? 1) <= PetRules.maximumFullnessToEat }

    /// The bowl was offered to a pet that could not manage another bite.
    func declineFood() {
        guard let current = pet else { return }
        PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.6)
        emit("fork.knife")
        say("\(current.name) could not manage another bite. Genuinely.")
    }

    /// The bag of food is out: the pet gets up and pays very close attention.
    func beginMealSession() {
        guard let current = pet else { return }
        endPetting()
        isBusyWithSession = true
        notifier.cancelAbandonmentNudge()
        PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.8)
        PetHaptics.shared.tap(intensity: 0.5, sharpness: 0.6)
    }

    /// A piece of food dropping into the bowl. Rate limited, because a poured bag is a
    /// great many pieces and every one of them wants a tap.
    func recordFoodInBowl() {
        guard Date.now.timeIntervalSince(lastPourTapAt) > 0.07 else { return }
        lastPourTapAt = .now
        PetHaptics.shared.tap(intensity: 0.25, sharpness: 0.9)
    }

    /// Food going on the floor instead of in the bowl. The pet takes this personally, so
    /// it gets a grumble rather than a pleasant little tap.
    func recordSpill() {
        guard let current = pet else { return }
        guard Date.now.timeIntervalSince(lastSpillAt) > 0.9 else { return }
        lastSpillAt = .now
        PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.7)
        PetHaptics.shared.tap(intensity: 0.8, sharpness: 0.85)
    }

    /// One mouthful out of the bowl. Returns false once the pet has had enough, which is
    /// what stops the feeding session.
    func recordBite() -> Bool {
        guard var current = pet else { return false }
        current.needs.fullness += PetRules.fullnessPerBite
        current.needs.clamp()
        current.recordCare(bond: PetRules.bondPerBite)
        pet = current

        PetHaptics.shared.tap(intensity: 0.5, sharpness: 0.35)
        // The munch buffer is most of a second of chewing on its own, so re-triggering it
        // per mouthful would only ever cut itself off.
        if Date.now.timeIntervalSince(lastMunchAt) > 0.7 {
            lastMunchAt = .now
            PetVoice.shared.play(current.voice.eating, voice: current.voice, volume: 0.7)
        }
        return current.needs.fullness < 1
    }

    func endMealSession(_ outcome: MealOutcome) {
        endSession()
        guard var current = pet else { return }
        if outcome.eaten > 0 {
            current.needs.fun += 0.04
            current.recordCare(bond: 2)
        }
        // Food on the floor is an insult as well as a waste, and it costs you either way.
        current.needs.affection -= min(
            Double(outcome.spilled) * PetRules.affectionLostPerSpill,
            PetRules.maximumAffectionLostToSpills
        )
        current.needs.clamp()
        pet = current

        // A mess overrides everything else the pet might have had to say about the meal.
        if outcome.spilled > outcome.eaten {
            PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.7)
            emit("exclamationmark.bubble.fill")
            say(Self.spillLine(for: current, outcome: outcome))
        } else if outcome.eaten == 0 {
            PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.5)
            say("\(current.name) never got so much as a crumb.")
        } else {
            PetHaptics.shared.celebrate()
            emit("fork.knife")
            say(Self.mealLine(for: current, outcome: outcome))
        }
        afterCare()
    }

    // MARK: Play sessions

    /// True when the pet has the energy to chase a toy around the screen.
    var canPlay: Bool { (pet?.needs.rest ?? 0) >= PetRules.minimumRestToPlay }

    /// Play was asked for while the pet is flat out.
    func declinePlay() {
        guard let current = pet else { return }
        PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.6)
        emit("moon.zzz.fill")
        say("\(current.name) is too tired to play. Put the phone down for a bit.")
    }

    /// A chase-the-toy session is starting: the pet is on its feet and watching the toy.
    func beginPlaySession() {
        guard let current = pet else { return }
        endPetting()
        isBusyWithSession = true
        notifier.cancelAbandonmentNudge()
        PetVoice.shared.play(current.voice.playing, voice: current.voice, volume: 0.8)
        PetHaptics.shared.tap(intensity: 0.5, sharpness: 0.6)
    }

    /// One successful pounce. The floating symbols and speech bubble live on the home
    /// screen, so the reward here is a noise, a buzz and the needs themselves.
    func recordCatch() {
        guard var current = pet else { return }
        current.needs.fun += PetRules.funPerCatch
        current.needs.rest -= PetRules.restCostPerCatch
        current.needs.fullness -= PetRules.fullnessCostPerCatch
        current.needs.clamp()
        current.recordCare(bond: PetRules.bondPerCatch)
        pet = current

        PetVoice.shared.play(current.voice.playing, voice: current.voice, volume: 0.7)
        PetHaptics.shared.tap(intensity: 0.85, sharpness: 0.5)
    }

    func endPlaySession(catches: Int) {
        endSession()
        guard let current = pet else { return }
        if catches == 0 {
            PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.5)
            say("\(current.name) never got a paw on the \(current.kind.toyName).")
        } else {
            PetHaptics.shared.celebrate()
            emit("sparkles")
            say(Self.playLine(for: current, catches: catches))
        }
        afterCare()
    }

    // MARK: Cuddles

    /// A cuddle is starting: stroke the pet drowsy, then pull a blanket over it. The
    /// stroking itself runs through `beginPetting()` and friends.
    func beginCuddleSession() {
        guard let current = pet else { return }
        endPetting()
        isBusyWithSession = true
        notifier.cancelAbandonmentNudge()
        PetVoice.shared.play(current.voice.comfort, voice: current.voice, volume: 0.7)
        PetHaptics.shared.tap(intensity: 0.4, sharpness: 0.25)
    }

    /// The pet has gone drowsy under your hand, and the blanket is now in play.
    func noteCuddleSleepy() {
        guard let current = pet else { return }
        PetVoice.shared.play(current.voice.comfort, voice: current.voice, volume: 0.55)
        PetHaptics.shared.tap(intensity: 0.35, sharpness: 0.2)
        emit("moon.zzz.fill")
    }

    /// Mid-cuddle and being ignored: the hand has stopped, or the blanket has come off.
    func noteCuddleFuss() {
        guard let current = pet else { return }
        PetVoice.shared.stopComfortLoop()
        PetVoice.shared.play(current.voice.lonely, voice: current.voice, volume: 0.85)
        PetHaptics.shared.tap(intensity: 0.6, sharpness: 0.7)
        emit("exclamationmark.bubble.fill")
    }

    /// The blanket made it over the pet.
    func recordTuckIn() {
        guard var current = pet else { return }
        current.needs.rest += PetRules.restPerTuckIn
        current.needs.affection += PetRules.affectionPerTuckIn
        current.needs.clamp()
        current.recordCare(bond: PetRules.bondPerTuckIn)
        pet = current

        PetVoice.shared.play(current.voice.comfort, voice: current.voice, volume: 0.9)
        PetHaptics.shared.celebrate()
        emit("moon.zzz.fill")
        afterCare()
    }

    func endCuddleSession(warmth: Double, tucked: Bool) {
        endPetting()
        endSession()
        guard var current = pet else { return }

        if tucked {
            say("\(current.name) is tucked in and fast asleep.")
        } else if warmth > 0.5 {
            // Nearly there: the stroking counted, even if the blanket never arrived.
            current.needs.affection += 0.05
            current.needs.clamp()
            current.recordCare(bond: 1)
            pet = current
            say("\(current.name) was almost asleep. The blanket never made it.")
        } else {
            PetVoice.shared.play(current.voice.lonely, voice: current.voice, volume: 0.6)
            say("\(current.name) didn't get much of a cuddle.")
        }
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
            greet(force: true)
        }
    }

    /// Something asked for from the wrist. The same care paths the notification actions
    /// use, so a meal from a watch is worth exactly what a meal from a nudge is.
    ///
    /// The pet goes back straight away rather than waiting for the throttle: the watch is
    /// sitting there with a spinner on it, and the wrist guessed the outcome optimistically
    /// so it needs the real answer to correct itself against.
    private func runErrand(_ errand: PetErrand) {
        switch errand {
        case .feed:
            feed()
        case .cuddle:
            quickCuddle()
        case .perform(let trick):
            perform(trick)
        }
        if let pet { watch.share(pet, force: true) }
    }

    // MARK: Tricks

    /// True when the pet is awake enough to take anything in.
    var canTrain: Bool { (pet?.needs.rest ?? 0) >= PetRules.minimumRestToTrain }

    /// A lesson was asked for while the pet can barely keep its eyes open.
    func declineTraining() {
        guard let current = pet else { return }
        PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.6)
        emit("moon.zzz.fill")
        say("\(current.name) is far too sleepy to learn anything.")
    }

    /// A lesson is starting: the pet sits up and watches your hands.
    func beginTrainingSession(_ trick: TrickKind) {
        guard let current = pet else { return }
        endPetting()
        endShowOff()
        isBusyWithSession = true
        notifier.cancelAbandonmentNudge()
        PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.7)
        PetHaptics.shared.tap(intensity: 0.45, sharpness: 0.6)
    }

    /// One go at a trick during a lesson.
    func attemptTrick(_ trick: TrickKind) -> TrickAttemptResult {
        attempt(trick, inLesson: true)
    }

    /// Telling the pet it did well, which is most of how a trick is learned.
    func praiseTrick(_ trick: TrickKind) {
        guard var current = pet else { return }
        current.recordTrickPraise(trick)
        current.needs.affection += PetRules.affectionPerPraise
        current.needs.clamp()
        current.recordCare(bond: PetRules.bondPerPraise)
        pet = current

        PetVoice.shared.play(current.voice.comfort, voice: current.voice, volume: 0.8)
        PetHaptics.shared.celebrate()
        emit("heart.fill")
        afterCare()
    }

    /// The hand drew something that isn't a signal the pet has ever been shown.
    func noteMuddledSignal() {
        guard let current = pet else { return }
        PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.35)
        PetHaptics.shared.tap(intensity: 0.3, sharpness: 0.4)
    }

    func endTrainingSession(_ outcome: TrainingOutcome) {
        endSession()
        guard let current = pet else { return }
        if outcome.isNewTrick {
            PetVoice.shared.play(current.voice.delighted, voice: current.voice)
            PetHaptics.shared.celebrate()
            emit("sparkles")
        }
        say(Self.lessonLine(for: current, outcome: outcome))
        afterCare()
    }

    /// Asking for a trick outside a lesson. The pet has to know it already, and can still
    /// fluff it if it is tired or the trick has gone rusty.
    func perform(_ trick: TrickKind) {
        guard let current = pet, current.knows(trick) else { return }
        endPetting()
        notifier.cancelAbandonmentNudge()

        let result = attempt(trick, inLesson: false)
        runShowOff(trick, succeeded: result.succeeded)
        say("\(current.name) \(result.succeeded ? Self.showOffLine(for: trick) : Self.confusedLine(for: trick))")
    }

    /// Rolls one attempt at a trick and banks everything that comes of it: what the pet
    /// learned, what it cost, and the noise it makes about the result.
    private func attempt(_ trick: TrickKind, inLesson: Bool) -> TrickAttemptResult {
        guard var current = pet else { return .missed }

        let succeeded = Double.random(in: 0...1) < current.chance(of: trick)
        let learning = inLesson ? 1 : PetRules.showOffLearning
        let isNew = current.recordTrickAttempt(trick, succeeded: succeeded, learning: learning)

        current.needs.fun += PetRules.funPerTrickAttempt
        current.needs.rest -= PetRules.restCostPerTrickAttempt
        current.needs.clamp()
        // Trying at all counts for something; getting it right counts for a good deal more.
        let reward = inLesson ? PetRules.bondPerTrickSuccess : PetRules.bondPerShowOff
        current.recordCare(bond: succeeded ? reward : 0.5)
        if isNew { current.recordCare(bond: PetRules.bondPerNewTrick) }
        pet = current

        if succeeded {
            PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.85)
            PetHaptics.shared.tap(intensity: 0.8, sharpness: 0.55)
            emit(isNew ? "sparkles" : trick.symbolName)
        } else {
            PetVoice.shared.play(current.voice.grumpy, voice: current.voice, volume: 0.45)
            PetHaptics.shared.tap(intensity: 0.35, sharpness: 0.3)
            emit("questionmark.circle")
        }
        afterCare()

        return TrickAttemptResult(succeeded: succeeded, isNew: isNew)
    }

    /// Steps the pose along for a trick performed on the home screen. The training
    /// screen drives its own routine off the lesson instead.
    private func runShowOff(_ trick: TrickKind, succeeded: Bool) {
        showOffTask?.cancel()
        showOff = trick
        showOffSucceeded = succeeded
        showOffRoutine = 0

        let startedAt = Date.now
        showOffTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(16))
                guard let self, !Task.isCancelled else { return }
                let progress = Date.now.timeIntervalSince(startedAt) / trick.routineLength
                guard progress < 1 else { break }
                self.showOffRoutine = progress
            }
            guard let self, !Task.isCancelled else { return }
            self.showOffRoutine = 0
            self.showOff = nil
        }
    }

    private func endShowOff() {
        showOffTask?.cancel()
        showOffTask = nil
        showOffRoutine = 0
        showOff = nil
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
        social.note("\(current.name) flung themselves at \(card.name).", symbolName: "heart.fill")
        current.needs.affection += 0.06
        current.needs.clamp()
        current.recordCare(bond: 1)
        pet = current
        PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.85)
        PetHaptics.shared.celebrate()
        emitBurst(["heart.fill", "sparkles", "heart.fill"])
        say("\(current.name) hugs \(card.name) like they'll never see them again.")
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
        PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.75)
        PetHaptics.shared.celebrate()
        emitBurst(["gift.fill", "sparkles", "heart.fill"])
        say("\(current.name) saved the best bit for \(card.name).")
        afterCare()
    }

    func invitePlay(_ card: PetCard) {
        guard let current = pet else { return }
        social.send(.playInvite, to: card)
        social.note("\(current.name) asked \(card.name) to play.", symbolName: "tennisball.fill")
        PetVoice.shared.play(current.voice.playing, voice: current.voice, volume: 0.9)
        PetHaptics.shared.tap(intensity: 0.7, sharpness: 0.5)
        emitBurst(["tennisball.fill", "sparkles"])
        say("\(current.name) is bouncing on the spot at \(card.name).")
    }

    private func receive(_ message: PetMessage, from card: PetCard) {
        guard var current = pet else { return }

        switch message {
        case .postcard, .postcardLikes, .postcardUnlike, .groupProbe, .groupOffer, .groupSync:
            // Postcards and their likes reach the feed through `social.onPostcard` and
            // `social.onLike`, and group traffic the group store through
            // `social.onGroupMessage`, so none of it gets this far. Listed so that adding
            // a message later can't be forgotten here.
            return

        case .hello:
            // A pet turning up is handled by `stageReunion`, which puts on the whole show.
            // A repeat hello is only the other phone refreshing its card, so it passes
            // quietly rather than setting the pet off all over again.
            current.needs.fun += 0.01
            current.needs.clamp()
            pet = current
            return

        case .nuzzle:
            current.needs.affection += 0.11
            social.note("\(card.name) barrelled into \(current.name) for a hug.",
                        symbolName: "heart.fill")
            PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.9)
            PetHaptics.shared.celebrate()
            emitBurst(["heart.fill", "heart.fill", "sparkles", "star.fill"])
            say("\(card.name) hugged \(current.name) so hard they both fell over.")

        case .treat:
            current.needs.fullness += 0.12
            current.needs.affection += 0.04
            social.note("\(card.name) shared a snack with \(current.name).", symbolName: "gift.fill")
            PetVoice.shared.play(current.voice.eating, voice: current.voice, volume: 0.85)
            PetHaptics.shared.celebrate()
            emitBurst(["gift.fill", "heart.fill", "sparkles"])
            say("\(card.name) brought \(current.name) a snack. Best day ever.")

        case .playInvite:
            current.needs.fun += 0.12
            current.needs.rest -= 0.03
            social.note("\(card.name) wants to play with \(current.name)!",
                        symbolName: "tennisball.fill")
            social.send(.playAccept, to: card)
            PetVoice.shared.play(current.voice.playing, voice: current.voice, volume: 1.0)
            PetHaptics.shared.celebrate()
            emitBurst(["tennisball.fill", "sparkles", "bolt.heart.fill"])
            say("\(card.name) wants to play and \(current.name) has already said yes.")

        case .playAccept:
            current.needs.fun += 0.16
            current.needs.rest -= 0.05
            social.note("\(current.name) and \(card.name) had a proper romp.",
                        symbolName: "sparkles")
            PetVoice.shared.play(current.voice.playing, voice: current.voice, volume: 1.0)
            PetHaptics.shared.celebrate()
            emitBurst(["sparkles", "star.fill", "heart.fill", "tennisball.fill"])
            say("\(current.name) and \(card.name) are tearing around together.")
        }

        current.needs.clamp()
        current.recordCare(bond: 2)
        pet = current
        afterCare()
    }

    // MARK: Postcards

    #if canImport(UIKit)
    /// A postcard goes out — a photo, or just a few words when `photo` is nil. The person
    /// did this on purpose, so the pet is allowed to make as much of it as it likes.
    @discardableResult
    func postPostcard(
        photo: UIImage?,
        caption: String,
        sticker: StickerPlacement,
        groupID: String? = nil
    ) -> PetPost? {
        guard var current = pet else { return nil }
        guard let post = postcards.post(
            photo: photo,
            caption: caption,
            sticker: sticker,
            groupID: groupID,
            pet: current,
            coordinate: locator.coordinate
        ) else { return nil }

        current.needs.fun += PetRules.funPerPostcard
        current.needs.affection += PetRules.affectionPerPostcard
        current.needs.clamp()
        current.recordCare(bond: PetRules.bondPerPostcard)
        pet = current

        PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.95)
        PetHaptics.shared.celebrate()
        emitBurst([photo == nil ? "pencil.and.scribble" : "camera.fill",
                   "sparkles", "heart.fill", "star.fill"])
        say(photo == nil ? Self.noteLine(for: current) : Self.postcardLine(for: current))
        afterCare()
        return post
    }
    #endif

    /// A postcard has arrived from somebody nearby.
    ///
    /// The log entry always happens, but the pet only pipes up if it is due a turn — an
    /// arriving postcard is something the person didn't ask for, so it goes through the
    /// same quarter-hourly gate as every other interruption.
    private func receivePostcard(_ envelope: PetPostEnvelope, from card: PetCard) {
        let before = postcards.posts.count
        postcards.receive(envelope, from: card)
        guard postcards.posts.count > before else { return }

        if envelope.post.isNote {
            social.note("\(card.name) sent over a note.", symbolName: "text.bubble.fill")
        } else {
            social.note("\(card.name) sent over a postcard.", symbolName: "photo.fill")
        }

        guard var current = pet else { return }
        current.needs.fun += PetRules.funPerPostcardSeen
        current.needs.clamp()
        pet = current
        persist()

        guard isForeground, !isBeingPetted, !isBusyWithSession, reunion == nil else { return }
        guard isCheckInDue else { return }
        lastPromptAt = .now
        PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.8)
        PetHaptics.shared.tap(intensity: 0.5, sharpness: 0.6)
        emitBurst(["photo.fill", "sparkles"])
        say("\(card.name) sent \(current.name) a postcard. Go and look.")
    }

    // MARK: Likes

    /// The person liked, or unliked, somebody else's postcard. They did this on purpose,
    /// so the reply is immediate — the quarter-hourly gate is only for things the pet
    /// brings up of its own accord.
    ///
    /// Returns whether the postcard has ended up liked.
    @discardableResult
    func toggleLike(on post: PetPost) -> Bool {
        guard var current = pet else { return false }
        guard postcards.toggleLike(on: post, by: current) else {
            // Taking a like back is a change of mind rather than an event. No fuss.
            PetHaptics.shared.tap(intensity: 0.3, sharpness: 0.3)
            return false
        }

        current.needs.fun += PetRules.funPerLikeGiven
        current.needs.clamp()
        current.recordCare(bond: PetRules.bondPerLikeGiven)
        pet = current

        PetHaptics.shared.tap(intensity: 0.7, sharpness: 0.5)
        emit("heart.fill")
        afterCare()
        return true
    }

    /// Likes arriving from somebody nearby. Only one of them is an event worth the pet's
    /// attention: somebody liking a postcard of its own.
    private func receiveLike(_ message: PetMessage, from card: PetCard) {
        switch message {
        case .postcardLikes(let incoming):
            let landed = postcards.receiveLikes(incoming, from: card)
            let mine = landed.filter { like in
                guard let post = postcards.posts.first(where: { $0.id == like.postID })
                else { return false }
                return postcards.isMine(post, pet: pet)
            }
            guard !mine.isEmpty else { return }
            celebrateLike(count: mine.count, by: card)

        case .postcardUnlike(let postID, let petID):
            postcards.receiveUnlike(postID: postID, petID: petID, from: card)

        default:
            break
        }
    }

    /// Somebody liked a postcard of yours. The pet has been admired by another pet, which
    /// is the single thing it would most like to happen to it, so it is paid like applause
    /// — but the interruption still waits its turn like every other one.
    private func celebrateLike(count: Int, by card: PetCard) {
        social.note(
            count == 1
                ? "\(card.name) liked your postcard."
                : "\(card.name) liked \(count) of your postcards.",
            symbolName: "heart.fill"
        )

        guard var current = pet else { return }
        // A phone that has been away for a week arrives with every like at once, and that
        // is a backlog rather than a moment.
        let paid = min(Double(count), PetRules.maximumLikesPaidAtOnce)
        current.needs.fun += PetRules.funPerLikeReceived * paid
        current.needs.affection += PetRules.affectionPerLikeReceived * paid
        current.needs.clamp()
        current.recordCare(bond: PetRules.bondPerLikeReceived)
        pet = current
        persist()

        guard isForeground, !isBeingPetted, !isBusyWithSession, reunion == nil else { return }
        guard isCheckInDue else { return }
        lastPromptAt = .now
        PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.95)
        PetHaptics.shared.celebrate()
        emitBurst(["heart.fill", "sparkles", "star.fill", "heart.fill"])
        say(Self.likeLine(for: current, by: card, count: count))
    }

    // MARK: Groups

    /// Group bookkeeping arriving from another phone. None of it is anything the pet
    /// needs to be told about — a roster catching up is not an event.
    private func receiveGroupMessage(_ message: PetMessage, from card: PetCard) {
        guard let myPetID, let current = pet else { return }

        switch message {
        case .groupProbe(let code):
            groups.handleProbe(code: code, from: card, myID: myPetID)
        case .groupOffer(let group):
            groups.handleOffer(group, as: current)
        case .groupSync(let group):
            groups.handleSync(group, myID: myPetID)
        default:
            break
        }
    }

    func createGroup(named name: String) -> PetGroup? {
        guard let current = pet else { return nil }
        let group = groups.create(named: name, as: current)
        PetHaptics.shared.celebrate()
        emitBurst(["person.2.fill", "sparkles"])
        say("\(current.name) started \(group.name). Hand the code out.")
        return group
    }

    func joinGroup(code: String) {
        guard let current = pet else { return }
        groups.beginJoin(code: code, as: current)
    }

    /// Getting into a friend's group is a social event, and those are the ones this pet
    /// cares about most.
    private func celebrateJoining(_ group: PetGroup) {
        guard var current = pet else { return }
        current.needs.fun += PetRules.funPerPostcard
        current.needs.affection += PetRules.affectionPerPostcard
        current.needs.clamp()
        current.recordCare(bond: PetRules.bondPerPostcard)
        pet = current

        PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.95)
        PetHaptics.shared.celebrate()
        emitBurst(["person.2.fill", "sparkles", "heart.fill", "star.fill"])
        social.note("\(current.name) joined \(group.name).", symbolName: "person.2.fill")
        say("\(current.name) is in \(group.name) now. Enormous news.")
        afterCare()
    }

    /// Leaves a group and takes its postcards with it — they were only ever for the
    /// people in it.
    func leaveGroup(_ group: PetGroup) {
        groups.forget(group)
        postcards.removePosts(inGroup: group.id)
    }

    // MARK: Reunions

    /// A friend has just come into range. As far as the pet is concerned this is the
    /// single greatest thing that has ever happened, so the whole screen is handed over
    /// to the reunion show.
    private func stageReunion(with card: PetCard) {
        guard var current = pet else { return }

        // Remembering the friend first means the show knows how many times these two have
        // met, and the friend is banked even if the show itself never gets to run.
        current.remember(friend: card)
        current.needs.fun += 0.04
        current.needs.affection += 0.02
        current.needs.clamp()
        pet = current
        persist()

        let record = current.friends.first { $0.id == card.id }
        let cast = ReunionCast(friend: card,
                               meetings: record?.meetings ?? 1,
                               bondTitle: record?.bondTitle ?? "Sniffing distance")

        // Nobody is looking, or these two only just did this: react, but don't replay the
        // whole cutscene.
        guard isForeground else {
            greetQuietly(card)
            return
        }
        if let last = lastReunionAt[card.id],
           Date.now.timeIntervalSince(last) < PetRules.reunionCooldown {
            greetQuietly(card)
            return
        }
        lastReunionAt[card.id] = .now

        if isBusyWithSession || reunion != nil {
            queuedReunion = cast
        } else {
            reunion = cast
        }
    }

    /// The small version, for when the big one can't run.
    private func greetQuietly(_ card: PetCard) {
        guard let current = pet else { return }
        PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.7)
        PetHaptics.shared.celebrate()
        emitBurst(["heart.fill", card.kind.symbolName])
        say("\(card.name) the \(card.kind.displayName.lowercased()) is here!")
    }

    /// The show is about to start: clear the decks.
    func beginReunion(_ cast: ReunionCast) {
        endPetting()
        endShowOff()
        notifier.cancelAbandonmentNudge()
    }

    /// Sound and haptics for the show, which leaves the noise-making where the rest of it
    /// lives rather than scattering it through a view.
    func reunionCue(_ cue: Reunion.Cue, friend card: PetCard) {
        guard let current = pet else { return }
        let friendVoice = card.kind.voice

        switch cue {
        case .gasp:
            PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.95)
            PetHaptics.shared.tap(intensity: 0.5, sharpness: 0.95)

        case .charge:
            PetVoice.shared.play(friendVoice.delighted, voice: friendVoice, volume: 0.95)
            PetHaptics.shared.tap(intensity: 0.4, sharpness: 0.35)

        case .impact:
            PetVoice.shared.play(current.voice.playing, voice: current.voice, volume: 1.0)
            PetHaptics.shared.celebrate()

        case .cheer:
            PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 0.9)

        case .friendCheer:
            PetVoice.shared.play(friendVoice.delighted, voice: friendVoice, volume: 0.9)

        case .firework:
            PetHaptics.shared.tap(intensity: 0.55, sharpness: 0.7)

        case .finale:
            PetVoice.shared.play(current.voice.delighted, voice: current.voice, volume: 1.0)
            PetHaptics.shared.celebrate()
        }
    }

    /// The curtain comes down. Time spent with a friend is worth more than anything the
    /// person can do on their own, and it is paid out here.
    func endReunion(_ cast: ReunionCast) {
        reunion = nil
        guard var current = pet else { return }

        current.needs.fun += PetRules.funPerReunion
        current.needs.affection += PetRules.affectionPerReunion
        current.needs.clamp()
        current.recordCare(bond: PetRules.bondPerReunion)
        pet = current

        social.note(Self.reunionNote(for: current, cast: cast), symbolName: "sparkles")
        PetVoice.shared.play(current.voice.comfort, voice: current.voice, volume: 0.8)
        PetHaptics.shared.celebrate()
        emitBurst(["heart.fill", "sparkles", "star.fill", cast.friend.kind.symbolName])
        say(Self.reunionLine(for: current, cast: cast))
        afterCare()
        flushQueuedReunion()
    }

    /// The reunion screen went away without finishing — the app was backgrounded, or the
    /// pet was let go mid-show.
    func cancelReunion() {
        guard reunion != nil else { return }
        reunion = nil
    }

    /// A session has ended, so anything that was waiting for the screen can have it.
    private func endSession() {
        isBusyWithSession = false
        flushQueuedReunion()
    }

    /// Presents a queued show, once whatever was in the way has had a moment to get off
    /// the screen — two full-screen covers cannot swap over in the same frame.
    private func flushQueuedReunion() {
        guard queuedReunion != nil else { return }
        Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(800))
            guard let self,
                  let next = self.queuedReunion,
                  self.isForeground,
                  !self.isBusyWithSession,
                  self.reunion == nil
            else { return }
            self.queuedReunion = nil
            self.reunion = next
        }
    }

    private func startNearbyIfNeeded() {
        guard hasStarted, owner.isSignedIn, preferences.nearbyEnabled, let petCard else {
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
        checkInIfDue()
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

    /// True once the pet is allowed to interrupt again. Every unprompted speech bubble —
    /// a greeting, a complaint about a table, a request for dinner — is behind this, so
    /// asking to be looked at happens about once a quarter of an hour instead of
    /// constantly. Anything the person did themselves still gets an instant reply.
    private var isCheckInDue: Bool {
        Date.now.timeIntervalSince(lastPromptAt) >= PetRules.promptInterval
    }

    /// The pet's quarter-hourly check-in: a complaint if it has been left on a table,
    /// otherwise whatever it would most like from you.
    private func checkInIfDue() {
        guard let pet, isForeground, !isBeingPetted, !isBusyWithSession, reunion == nil else { return }
        guard isCheckInDue else { return }
        lastPromptAt = .now

        if pet.isAsleep {
            // Its own bedtime, so there is nothing to complain about and nothing being
            // asked for. Being put down is what it wanted.
            noteSleeping(pet)
        } else if holdSensor.hasBeenAbandoned {
            PetVoice.shared.play(pet.voice.lonely, voice: pet.voice, volume: 1.0)
            PetHaptics.shared.tap(intensity: 0.9, sharpness: 0.8)
            emit("exclamationmark.bubble.fill")
            say(Self.setDownLine(for: pet))
            notifier.scheduleAbandonmentNudge(for: pet, after: PetRules.promptInterval)
        } else {
            let happy = pet.moodScore > 0.6
            PetVoice.shared.play(happy ? pet.voice.delighted : pet.voice.lonely,
                                 voice: pet.voice, volume: 0.85)
            emit(happy ? "sparkles" : "heart")
            say(Self.checkInLine(for: pet))
        }
    }

    /// The hello when the app comes to the front. `force` is for a notification the person
    /// actually tapped, which deserves an answer whatever the clock says.
    private func greet(force: Bool = false) {
        guard let pet, force || isCheckInDue else { return }
        lastPromptAt = .now
        // Opening the app in the middle of the night finds the pet asleep rather than
        // waiting up pointedly, which is the whole idea.
        if pet.isAsleep {
            noteSleeping(pet)
            return
        }
        let happy = pet.moodScore > 0.6
        PetVoice.shared.play(happy ? pet.voice.delighted : pet.voice.lonely, voice: pet.voice)
        emit(happy ? "sparkles" : "heart")
        say(Self.greetingLine(for: pet))
    }

    /// The pet, found asleep. Quiet on purpose: a soft noise and one line, never a
    /// demand, and no haptic at all.
    private func noteSleeping(_ pet: Pet) {
        PetVoice.shared.play(pet.voice.comfort, voice: pet.voice, volume: 0.45)
        emit("moon.zzz.fill")
        say(Self.sleepingLine(for: pet))
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
        saveTask?.cancel()
        saveTask = nil
        guard let pet else { return }
        lastSavedAt = .now
        PetArchive.save(pet)
        // Throttled inside `share`, so this being on every save is cheaper than it looks.
        watch.share(pet)
    }

    /// Saves once the changes stop coming, for controls that fire continuously.
    private func scheduleSave(thenRescheduleNudges: Bool = false) {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(700))
            guard let self, !Task.isCancelled else { return }
            self.persist()
            if thenRescheduleNudges, let pet = self.pet {
                self.notifier.rescheduleNeglectLadder(for: pet)
            }
        }
    }

    private func autosave(_ now: Date) {
        guard let pet, now.timeIntervalSince(lastSavedAt) > 20 else { return }
        lastSavedAt = now
        PetArchive.save(pet)
        watch.share(pet)
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

    /// A whole handful of symbols at once, staggered just enough to read as a spray
    /// rather than one fat symbol. Used for anything to do with friends, where a single
    /// polite heart would be underselling it.
    func emitBurst(_ symbols: [String]) {
        for (index, symbol) in symbols.enumerated() {
            guard index > 0 else {
                emit(symbol)
                continue
            }
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(100 * index))
                self?.emit(symbol)
            }
        }
    }

    /// The one-line summary shown under the pet.
    var statusLine: String {
        guard let pet else { return "" }
        if isBeingPetted {
            return pet.kind.canPurr ? "Purring." : "Making an extremely happy noise."
        }
        // Being asleep or waiting out your day comes before any complaint: a pet keeping
        // your own hours is not being neglected, and shouldn't be made to read that way.
        switch pet.phase {
        case .asleep:
            return Self.sleepingStatus(for: pet)
        case .away:
            return Self.awayStatus(for: pet)
        case .awake:
            break
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

    /// The symbol shown beside the status line while the pet is keeping your hours.
    var phaseSymbol: String? {
        guard let pet, !isBeingPetted else { return nil }
        return pet.phase == .awake ? nil : pet.phase.symbolName
    }

    private static func sleepingStatus(for pet: Pet) -> String {
        guard let waking = pet.schedule.nextChange(after: .now) else {
            return "Fast asleep. Needs hardly move while \(pet.name) is out cold."
        }
        let time = waking.formatted(date: .omitted, time: .shortened)
        return "Fast asleep until \(time). Barely a need moves overnight."
    }

    private static func awayStatus(for pet: Pet) -> String {
        guard let home = pet.schedule.nextChange(after: .now) else {
            return "\(pet.name) is dozing until you're free. Needs are on a slow drip."
        }
        let time = home.formatted(date: .omitted, time: .shortened)
        return "Holding the fort until \(time). Napping mostly, and taking it slowly."
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

    /// Found asleep at its own bedtime. Warm, never guilt-inducing: the pet is having a
    /// lovely time and is not owed anything.
    private static func sleepingLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name) is asleep in a perfect circle. Don't let it stop you."
        case .dog: "\(pet.name) is out cold with all four paws in the air."
        case .bunny: "\(pet.name) is flopped over sideways, dead to the world."
        case .dragon: "\(pet.name) is banked down to embers, snoring smoke rings."
        case .monkey: "\(pet.name) is asleep upside down. Somehow comfortable."
        }
    }

    private static func pettingLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name) leans into it, eyes shut."
        case .dog: "\(pet.name)'s whole body is wagging."
        case .bunny: "\(pet.name) has flopped over. That's a compliment."
        case .dragon: "\(pet.name) rumbles like a small furnace."
        case .monkey: "\(pet.name) grabs your thumb with both hands and holds on."
        }
    }

    private static func postcardLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name) is on a postcard and has already started posing for the next one."
        case .dog: "\(pet.name) is on a postcard! \(pet.name) is on a postcard!"
        case .bunny: "\(pet.name) went very still for the photo. It came out beautifully."
        case .dragon: "\(pet.name) approves of being immortalised. Finally."
        case .monkey: "\(pet.name) got in front of the lens on purpose. Obviously."
        }
    }

    /// A note going out. No camera came into it, but the pet is still on the front of
    /// the card, which as far as the pet is concerned is the important part.
    private static func noteLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name) sat on the card while you were writing. It went out anyway."
        case .dog: "\(pet.name) has no idea what it says and is thrilled about it!"
        case .bunny: "\(pet.name) read it twice and is quietly very pleased."
        case .dragon: "\(pet.name) would have chosen grander words, but agrees with the sentiment."
        case .monkey: "\(pet.name) tried to add a bit at the end. You caught it in time."
        }
    }

    /// Being liked by another pet. Shamelessly overplayed, because from where the pet is
    /// standing this is a standing ovation.
    private static func likeLine(for pet: Pet, by card: PetCard, count: Int) -> String {
        guard count == 1 else {
            return "\(card.name) went through \(pet.name)'s postcards liking every single one. \(pet.name) is beside themselves."
        }
        switch pet.kind {
        case .cat: return "\(card.name) liked \(pet.name)'s postcard. \(pet.name) is pretending not to have noticed."
        case .dog: return "\(card.name) liked \(pet.name)'s postcard! \(pet.name) has read it four times!"
        case .bunny: return "\(card.name) liked \(pet.name)'s postcard. \(pet.name) has gone quite pink."
        case .dragon: return "\(card.name) liked \(pet.name)'s postcard, as was only proper."
        case .monkey: return "\(card.name) liked \(pet.name)'s postcard, and \(pet.name) is already planning the next one."
        }
    }

    private static func playLine(for pet: Pet, catches: Int) -> String {
        let tally = catches == 1 ? "One catch" : "\(catches) catches"
        return "\(tally). \(playLine(for: pet))"
    }

    private static func playLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name) ambushes your thumb."
        case .dog: "\(pet.name) brings the ball back. Twice."
        case .bunny: "\(pet.name) binkies across the screen."
        case .dragon: "\(pet.name) chases a spark round the glass."
        case .monkey: "\(pet.name) swipes the bell and shakes it triumphantly."
        }
    }

    private static func mealLine(for pet: Pet, outcome: MealOutcome) -> String {
        if outcome.spilled > 4 {
            return "\(eatingLine(for: pet)) \(spillLine(for: pet, outcome: outcome))"
        }
        if pet.needs.fullness >= 1 {
            return "\(eatingLine(for: pet)) Completely stuffed now."
        }
        if outcome.leftInBowl > 0 {
            return "\(eatingLine(for: pet)) There's some left for later."
        }
        return "Bowl licked clean. \(eatingLine(for: pet))"
    }

    /// What the pet has to say about the food you put on the floor. Spilling a whole bag
    /// is worse than spilling a handful, and the pet is quite clear about the difference.
    private static func spillLine(for pet: Pet, outcome: MealOutcome) -> String {
        guard outcome.spilled > outcome.eaten else {
            return sulkLine(for: pet)
        }
        let mess = outcome.eaten == 0 ? "All of that" : "Most of that"
        return "\(mess) went on the floor. \(sulkLine(for: pet))"
    }

    private static func sulkLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name) is staring at the mess. Then at you."
        case .dog: "\(pet.name) huffs at the waste of a perfectly good dinner."
        case .bunny: "\(pet.name) thumps a foot at the mess."
        case .dragon: "\(pet.name) smoulders quietly at the mess."
        case .monkey: "\(pet.name) chatters at the mess, then at you."
        }
    }

    private static func eatingLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name) inhales it, then asks about seconds."
        case .dog: "\(pet.name) got through that in about four seconds."
        case .bunny: "\(pet.name) worked through it leaf by leaf."
        case .dragon: "\(pet.name) crunched the lot and burped a spark."
        case .monkey: "\(pet.name) peeled it properly and everything."
        }
    }

    /// The verdict at the end of a lesson.
    private static func lessonLine(for pet: Pet, outcome: TrainingOutcome) -> String {
        if outcome.isNewTrick {
            return "\(pet.name) has learned to \(outcome.trick.displayName.lowercased())!"
        }
        if outcome.attempts == 0 {
            return "\(pet.name) sat waiting for a signal that never came."
        }
        if outcome.successes == 0 {
            return "\(pet.name) still hasn't the faintest idea what \(outcome.trick.cue.dropLast()) means."
        }

        let tally = "\(outcome.successes) out of \(outcome.attempts)"
        if pet.mastery(of: outcome.trick) >= PetRules.reliableMastery {
            return "\(tally). \(outcome.trick.displayName) is rock solid now."
        }
        return "\(tally). \(outcome.trick.displayName) is coming along."
    }

    private static func showOffLine(for trick: TrickKind) -> String {
        switch trick {
        case .sit: "plants itself down and waits, extremely pleased about it."
        case .paw: "lifts a paw into your hand."
        case .speak: "answers you, loudly."
        case .spin: "turns a neat circle on the spot."
        case .jump: "springs clean off the glass."
        case .rollOver: "flops over and rolls the whole way round."
        }
    }

    private static func confusedLine(for trick: TrickKind) -> String {
        "tilts its head. No \(trick.displayName.lowercased()) this time."
    }

    private static func setDownLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "\(pet.name): \"…you're just going to leave me here?\""
        case .dog: "\(pet.name) barks. You are being called back."
        case .bunny: "\(pet.name) thumps a foot at you."
        case .dragon: "\(pet.name) roars quietly at the ceiling."
        case .monkey: "\(pet.name) chatters after you. Loudly."
        }
    }

    /// What the pet says when it interrupts you — once a quarter of an hour at most.
    private static func checkInLine(for pet: Pet) -> String {
        guard let need = pet.neediest else {
            return "\(pet.name) checks in. Nothing needed, just saying hello."
        }
        return "\(pet.name) wants a word. \(wish(for: need, pet: pet))"
    }

    /// The verdict once two pets have finished losing their minds at each other.
    private static func reunionLine(for pet: Pet, cast: ReunionCast) -> String {
        if cast.isFirstMeeting {
            return "\(pet.name) and \(cast.friend.name) are best friends now. It's decided."
        }
        if cast.meetings >= 5 {
            return "\(pet.name) and \(cast.friend.name), reunited for the \(ordinal(cast.meetings)) time. Still this excited."
        }
        return "\(pet.name) has not stopped bouncing since \(cast.friend.name) arrived."
    }

    private static func reunionNote(for pet: Pet, cast: ReunionCast) -> String {
        cast.isFirstMeeting
            ? "\(pet.name) and \(cast.friend.name) met and instantly became inseparable."
            : "\(pet.name) and \(cast.friend.name) lost their minds at each other again."
    }

    private static func ordinal(_ value: Int) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter.string(from: NSNumber(value: value)) ?? "\(value)th"
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
