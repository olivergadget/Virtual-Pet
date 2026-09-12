import Foundation
import UserNotifications

/// Schedules the nagging. A digital pet that can only reach you while the app is open
/// isn't a pet, it's a screensaver — so an escalating ladder of local notifications is
/// laid down every time the pet is tended or the app goes to the background.
@Observable
final class PetNotifier {
    static let careCategory = "PET_CARE"

    enum Action: String {
        case pet = "PET_ACTION"
        case feed = "FEED_ACTION"
    }

    private static let neglectPrefix = "petphone.neglect."
    private static let abandonmentIdentifier = "petphone.abandoned"

    private(set) var authorization: UNAuthorizationStatus = .notDetermined
    var isEnabled = true

    var isAuthorized: Bool {
        authorization == .authorized || authorization == .provisional || authorization == .ephemeral
    }

    private let center = UNUserNotificationCenter.current()

    func registerCategories() {
        let category = UNNotificationCategory(
            identifier: Self.careCategory,
            actions: [
                UNNotificationAction(identifier: Action.pet.rawValue,
                                     title: "Pet them", options: [.foreground]),
                UNNotificationAction(identifier: Action.feed.rawValue,
                                     title: "Feed them", options: [.foreground])
            ],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func refreshAuthorization() async {
        let settings = await center.notificationSettings()
        authorization = settings.authorizationStatus
    }

    @discardableResult
    func requestAuthorization() async -> Bool {
        let granted = (try? await center.requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        await refreshAuthorization()
        return granted
    }

    // MARK: Scheduling

    /// Replaces the whole neglect ladder. Call whenever the pet is cared for, and again
    /// when the app leaves the foreground.
    func rescheduleNeglectLadder(for pet: Pet) {
        let identifiers = (0..<Self.ladder(for: pet).count).map { Self.neglectPrefix + String($0) }
        center.removePendingNotificationRequests(withIdentifiers: identifiers)
        guard isEnabled, isAuthorized else { return }

        let alreadyElapsed = pet.timeSinceTended
        for (index, nudge) in Self.ladder(for: pet).enumerated() {
            let delay = nudge.after - alreadyElapsed
            guard delay > 5 else { continue }

            let content = UNMutableNotificationContent()
            content.title = nudge.title
            content.body = nudge.body
            content.sound = .default
            content.categoryIdentifier = Self.careCategory
            content.threadIdentifier = "petphone.care"

            let request = UNNotificationRequest(
                identifier: Self.neglectPrefix + String(index),
                content: content,
                trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
            )
            center.add(request)
        }
    }

    /// A short-fuse reminder used when the phone is put down and walked away from.
    func scheduleAbandonmentNudge(for pet: Pet, after delay: TimeInterval = 12 * 60) {
        cancelAbandonmentNudge()
        guard isEnabled, isAuthorized else { return }

        let content = UNMutableNotificationContent()
        content.title = "\(pet.name) is on their own"
        content.body = Self.abandonmentLine(for: pet)
        content.sound = .default
        content.categoryIdentifier = Self.careCategory
        content.threadIdentifier = "petphone.care"

        let request = UNNotificationRequest(
            identifier: Self.abandonmentIdentifier,
            content: content,
            trigger: UNTimeIntervalNotificationTrigger(timeInterval: delay, repeats: false)
        )
        center.add(request)
    }

    func cancelAbandonmentNudge() {
        center.removePendingNotificationRequests(withIdentifiers: [Self.abandonmentIdentifier])
    }

    func cancelEverything() {
        center.removeAllPendingNotificationRequests()
    }

    // MARK: Copy

    private struct Nudge {
        let after: TimeInterval
        let title: String
        let body: String
    }

    private static func ladder(for pet: Pet) -> [Nudge] {
        let name = pet.name
        let minutes = 60.0
        let hours = 3_600.0

        switch pet.kind {
        case .cat:
            return [
                Nudge(after: 45 * minutes, title: "\(name) is doing the stare",
                      body: "You know the one. Behind the ears would fix it."),
                Nudge(after: 3 * hours, title: "\(name) knocked something off a shelf",
                      body: "Allegedly an accident. Attention is the recommended treatment."),
                Nudge(after: 8 * hours, title: "\(name) is pointing at an empty bowl",
                      body: "Loudly. With their whole body."),
                Nudge(after: 20 * hours, title: "\(name) hasn't purred since you left",
                      body: "Pick the phone up and that changes immediately."),
                Nudge(after: 36 * hours, title: "\(name) has given up on the door",
                      body: "Curled up facing the wall. One hand would help.")
            ]
        case .dog:
            return [
                Nudge(after: 45 * minutes, title: "\(name) heard something!",
                      body: "It was nothing. But now they're awake and want you."),
                Nudge(after: 3 * hours, title: "\(name) has been holding a toy for a while",
                      body: "Just standing there. Holding it. Waiting."),
                Nudge(after: 8 * hours, title: "\(name) is hungry",
                      body: "Sitting very politely next to where the food lives."),
                Nudge(after: 20 * hours, title: "\(name) barked at the door again",
                      body: "Convinced every footstep outside is you coming back."),
                Nudge(after: 36 * hours, title: "\(name) is sleeping on your side of the bed",
                      body: "It smells like you. It's not the same, though.")
            ]
        case .bunny:
            return [
                Nudge(after: 45 * minutes, title: "\(name) thumped",
                      body: "Once. Firmly. You have been noted."),
                Nudge(after: 3 * hours, title: "\(name) has rearranged everything",
                      body: "A statement has been made about your absence."),
                Nudge(after: 8 * hours, title: "\(name) is out of greens",
                      body: "Nose twitching at an empty bowl."),
                Nudge(after: 20 * hours, title: "\(name) is hiding behind the sofa",
                      body: "Not scared. Sulking. There's a difference."),
                Nudge(after: 36 * hours, title: "\(name) has stopped binkying",
                      body: "A held hand is the only known cure.")
            ]
        case .dragon:
            return [
                Nudge(after: 45 * minutes, title: "\(name) let out a small puff of smoke",
                      body: "Impatience, rendered in vapour."),
                Nudge(after: 3 * hours, title: "\(name) is guarding your phone jealously",
                      body: "It's their hoard now. You may visit it."),
                Nudge(after: 8 * hours, title: "\(name)'s fire is running low",
                      body: "Needs feeding before the rumbling stops."),
                Nudge(after: 20 * hours, title: "\(name) has gone cold",
                      body: "Scales dull, embers out. Warm them up."),
                Nudge(after: 36 * hours, title: "\(name) is curled around nothing",
                      body: "A dragon without a keeper is just a very sad lizard.")
            ]
        }
    }

    private static func abandonmentLine(for pet: Pet) -> String {
        switch pet.kind {
        case .cat: "You put \(pet.name) down and walked off. Bold."
        case .dog: "\(pet.name) is sitting exactly where you left them. Exactly."
        case .bunny: "\(pet.name) has been very still and very alone."
        case .dragon: "\(pet.name) is cooling off on a cold, flat surface."
        }
    }
}

/// Bridges notification taps back into the app. Delegate callbacks can arrive on any
/// queue, so everything hops to the main actor before it touches the pet.
nonisolated final class PetNotificationRouter: NSObject, UNUserNotificationCenterDelegate {
    static let shared = PetNotificationRouter()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        // Let the pet interrupt you even when you already have the app open.
        completionHandler([.banner, .list, .sound])
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let identifier = response.actionIdentifier
        Task { @MainActor in
            PetWorld.shared.handleNotificationAction(identifier)
        }
        completionHandler()
    }
}
