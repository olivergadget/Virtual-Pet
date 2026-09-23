import Foundation
#if canImport(WatchConnectivity)
import WatchConnectivity
#endif

/// Something the watch asks the phone to do on the pet's behalf.
///
/// The phone owns the pet, so the watch never decides anything for longer than it takes
/// the answer to come back. Everything the wrist can do is one of these.
///
/// Nonisolated because an errand is unpacked on the background thread Watch Connectivity
/// delivers it on, before anything main-actor gets involved.
nonisolated enum PetErrand: Sendable, Equatable {
    case feed
    case cuddle
    case perform(TrickKind)

    /// The wire form. Kept to strings so an errand sent by a newer build is ignored by an
    /// older one rather than crashing it.
    var payload: [String: String] {
        switch self {
        case .feed: ["errand": "feed"]
        case .cuddle: ["errand": "cuddle"]
        case .perform(let trick): ["errand": "perform", "trick": trick.rawValue]
        }
    }

    init?(payload: [String: Any]) {
        switch payload["errand"] as? String {
        case "feed": self = .feed
        case "cuddle": self = .cuddle
        case "perform":
            guard let raw = payload["trick"] as? String, let trick = TrickKind(rawValue: raw) else {
                return nil
            }
            self = .perform(trick)
        default:
            return nil
        }
    }
}

/// Keeps the pet on the phone and the pet on the wrist telling the same story.
///
/// The phone is the only place the simulation actually runs, so the traffic is lopsided on
/// purpose: the phone pushes whole pets, and the watch sends back small errands. State goes
/// out as an *application context*, which keeps only the newest value — a pet from four
/// minutes ago is of no interest once a newer one exists. Errands go out as messages when
/// the counterpart is awake, and as queued transfers when it isn't, because a tap on the
/// wrist should survive the phone being in a pocket.
///
/// Both apps create one of these. `onPet` is what the watch listens to; `onErrand` is what
/// the phone listens to. Neither side has to know which one it is.
@Observable
final class PetSync {
    static let shared = PetSync()

    /// True when the counterpart app can be talked to this second.
    private(set) var isReachable = false

    /// True when there is a counterpart at all — a watch on the wrist with the app
    /// installed, or, from the watch's side, a phone that has the app.
    private(set) var hasCounterpart = false

    /// When a pet last arrived or went out. `nil` until the two have spoken.
    private(set) var lastSyncAt: Date?

    /// A fresh pet has arrived from the counterpart. The watch uses this.
    var onPet: ((Pet) -> Void)?

    /// The pet has been let go on the phone. Without this the watch would be left showing
    /// a pet that no longer exists, forever.
    var onRelease: (() -> Void)?

    /// The watch has asked for something. Only ever called on the phone.
    var onErrand: ((PetErrand) -> Void)?

    /// Called after anything at all arrives. The watch uses it to close out the background
    /// task it was woken by, once there is nothing left to hand over.
    var onDelivery: (() -> Void)?

    private var isActivated = false
    private var lastShareAt: Date?

    /// How often the phone is willing to push a whole pet at the watch, outside the
    /// moments that force it.
    private static let shareInterval: TimeInterval = 10

    #if canImport(WatchConnectivity)
    /// Held because `WCSession.delegate` is weak.
    private var delegate: SyncDelegate?
    #endif

    private init() {}

    // MARK: Lifecycle

    /// Starts talking to the counterpart. Safe to call repeatedly — the session is only set
    /// up once, and later calls just re-check where things stand — so every `scenePhase`
    /// change can go through it.
    func activate() {
        #if canImport(WatchConnectivity)
        guard WCSession.isSupported() else { return }
        guard !isActivated else {
            // Already talking. Re-check anyway, because coming back to the foreground is
            // exactly when the counterpart may have missed something.
            refreshStatus()
            return
        }
        isActivated = true

        let delegate = SyncDelegate(owner: self)
        self.delegate = delegate
        WCSession.default.delegate = delegate
        WCSession.default.activate()
        // No status check here: activation is asynchronous, so there is nothing to read
        // yet. The delegate's `activationDidCompleteWith` is what fills it in.
        #endif
    }

    // MARK: Sending

    /// Phone → watch. Overwrites anything still queued, because only the newest pet matters.
    ///
    /// Throttled, because the phone saves the pet far more often than a wrist could
    /// possibly care about. `force` is for the moments that genuinely can't wait: a fresh
    /// adoption, the answer to something the watch asked for, or the app going away.
    ///
    /// Silently does nothing when there is no watch to send to, which is the normal case
    /// for most people and is not worth reporting.
    func share(_ pet: Pet, force: Bool = false) {
        #if canImport(WatchConnectivity)
        guard isActivated, canSend else { return }
        if !force, let lastShareAt, Date.now.timeIntervalSince(lastShareAt) < Self.shareInterval {
            return
        }
        guard let data = Self.encode(pet) else { return }
        do {
            try WCSession.default.updateApplicationContext([Self.petKey: data])
            lastShareAt = .now
            lastSyncAt = .now
        } catch {
            // Nothing useful to do about it: the next save tries again with a newer pet.
        }
        #endif
    }

    /// Phone → watch. The pet has been let go, so the watch should stop showing one.
    func shareRelease() {
        #if canImport(WatchConnectivity)
        guard isActivated, canSend else { return }
        try? WCSession.default.updateApplicationContext([Self.releasedKey: true])
        lastShareAt = .now
        #endif
    }

    /// Watch → phone. Tries to be instant, and falls back to a queued delivery that
    /// outlives the app going to sleep.
    func send(_ errand: PetErrand) {
        #if canImport(WatchConnectivity)
        guard isActivated, canSend else { return }
        let session = WCSession.default
        let payload = errand.payload

        guard session.isReachable else {
            session.transferUserInfo(payload)
            return
        }
        session.sendMessage(payload, replyHandler: nil) { _ in
            // The phone went away between the check and the send. Queue it instead, so the
            // pet still gets fed — just later than the person expected.
            session.transferUserInfo(payload)
        }
        #endif
    }

    #if canImport(WatchConnectivity)
    /// True when there is an activated session with something on the other end.
    private var canSend: Bool {
        let session = WCSession.default
        guard session.activationState == .activated else { return false }
        #if os(iOS)
        // Sending to a phone with no watch paired throws rather than no-ops.
        return session.isPaired && session.isWatchAppInstalled
        #else
        return true
        #endif
    }
    #endif

    // MARK: Receiving

    fileprivate func receive(_ pet: Pet) {
        lastSyncAt = .now
        onPet?(pet)
    }

    fileprivate func receive(_ errand: PetErrand) {
        onErrand?(errand)
    }

    fileprivate func receiveRelease() {
        lastSyncAt = .now
        onRelease?()
    }

    /// Called once per delivery, after everything in it has been handed on.
    fileprivate func noteDelivery() {
        onDelivery?()
    }

    /// Asked for the pet as it stands the moment a session becomes usable.
    ///
    /// Activating a `WCSession` is asynchronous, so anything the app tries to send while
    /// starting up is sent into a session that isn't ready and is quietly dropped. This is
    /// how the first pet of the session actually gets across.
    var currentPet: (() -> Pet?)?

    /// True while Watch Connectivity still has something it hasn't handed over yet. The
    /// watch has to keep its background task open until this goes false, or it loses the
    /// data it was woken up for.
    nonisolated var hasPendingContent: Bool {
        #if canImport(WatchConnectivity)
        WCSession.default.hasContentPending
        #else
        false
        #endif
    }

    fileprivate func refreshStatus() {
        #if canImport(WatchConnectivity)
        let session = WCSession.default
        // Reachability and pairing say nothing until activation has finished, and asking
        // early logs an error for each one. Whatever prompted this will come round again:
        // activation itself always reports back through the delegate.
        guard session.activationState == .activated else { return }
        isReachable = session.isReachable
        #if os(iOS)
        hasCounterpart = session.isPaired && session.isWatchAppInstalled
        #else
        hasCounterpart = session.isCompanionAppInstalled
        #endif

        // A status change means something just became possible: the session finished
        // activating, the watch came back into range, or the app was installed onto it.
        // Each of those deserves the newest pet — and since activation is asynchronous,
        // this is what actually gets the first pet of the session across.
        if canSend, let pet = currentPet?() {
            share(pet, force: true)
        }
        #endif
    }

    // MARK: Wire format

    /// A pet travels as the same JSON it is saved as, so there is only one format to keep
    /// working and an old build can read a new build's pet.
    nonisolated static let petKey = "pet"
    /// Marks a context that means "there is no pet any more" — distinct from an empty one,
    /// which only ever means the two haven't spoken yet.
    nonisolated static let releasedKey = "released"

    // Both run on the main actor, where the pet itself lives. Only the raw `Data` crosses
    // to and from the background thread Watch Connectivity works on.
    static func encode(_ pet: Pet) -> Data? {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        return try? encoder.encode(pet)
    }

    static func decode(_ data: Data) -> Pet? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Pet.self, from: data)
    }
}

#if canImport(WatchConnectivity)
/// The `WCSession` delegate, kept separate from `PetSync` because every one of these
/// methods arrives on a background thread while `PetSync` itself lives on the main actor.
/// Payloads are unpacked here and only the finished value is handed across.
private nonisolated final class SyncDelegate: NSObject, WCSessionDelegate {
    private let owner: PetSync

    init(owner: PetSync) {
        self.owner = owner
        super.init()
    }

    func session(_ session: WCSession,
                 activationDidCompleteWith activationState: WCSessionActivationState,
                 error: (any Error)?) {
        notifyStatusChanged()
    }

    func sessionReachabilityDidChange(_ session: WCSession) {
        notifyStatusChanged()
    }

    func session(_ session: WCSession, didReceiveApplicationContext applicationContext: [String: Any]) {
        deliver(applicationContext)
    }

    func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        deliver(message)
    }

    func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        deliver(userInfo)
    }

    #if os(iOS)
    func sessionWatchStateDidChange(_ session: WCSession) {
        notifyStatusChanged()
    }

    func sessionDidBecomeInactive(_ session: WCSession) {}

    /// Someone has switched to a different Apple Watch. Reactivating hands the session to
    /// the new one; without this the app is left talking to a watch that has gone.
    func sessionDidDeactivate(_ session: WCSession) {
        session.activate()
    }
    #endif

    // MARK: Unpacking

    /// Pulls whatever we understand out of a payload and hands it to the main actor. A
    /// dictionary that holds nothing recognisable is dropped without comment — it came from
    /// a build that knows something this one doesn't.
    private func deliver(_ payload: [String: Any]) {
        let owner = self.owner
        // Picked apart here, while still on the delivery thread, so that nothing but plain
        // `Sendable` values — some bytes, a flag, an errand — crosses to the main actor.
        // The pet itself is decoded over there, where it belongs.
        let petData = payload[PetSync.petKey] as? Data
        let wasReleased = payload[PetSync.releasedKey] as? Bool == true
        let errand = PetErrand(payload: payload)
        guard petData != nil || wasReleased || errand != nil else { return }

        Task { @MainActor in
            if let petData, let pet = PetSync.decode(petData) {
                owner.receive(pet)
            }
            if wasReleased {
                owner.receiveRelease()
            }
            if let errand {
                owner.receive(errand)
            }
            owner.noteDelivery()
        }
    }

    private func notifyStatusChanged() {
        let owner = self.owner
        Task { @MainActor in owner.refreshStatus() }
    }
}
#endif
