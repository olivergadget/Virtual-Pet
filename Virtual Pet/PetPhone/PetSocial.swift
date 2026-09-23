import Foundation
import Network

/// Everything one pet can say to another.
enum PetMessage: Codable, Sendable {
    case hello(PetCard)
    case nuzzle
    case treat
    case playInvite
    case playAccept
    /// A photo of what somebody is up to, with their pet on the front of it. Much the
    /// largest thing that travels between two phones — see ``PostImage/maximumBytes``.
    case postcard(PetPostEnvelope)
    /// Postcards somebody liked. A list rather than a single like, because a phone coming
    /// into range is told about every like of ours it missed in one go.
    case postcardLikes([PostLike])
    /// A like being taken back.
    case postcardUnlike(postID: String, petID: String)
    /// "Has anybody got the group this code opens?" The one group message that really is
    /// a broadcast; the rosters themselves only ever go to members.
    case groupProbe(String)
    /// The answer to a probe: here is the group your code opens.
    case groupOffer(PetGroup)
    /// A copy of a group's log, for a member to merge with their own.
    case groupSync(PetGroup)
}

/// Discovers other people's pets on the same Wi-Fi — or directly over peer-to-peer radio
/// with no network at all — and keeps a log of what happened when they met.
@Observable
final class PetSocial {
    struct Encounter: Identifiable, Sendable {
        let id = UUID()
        let date: Date
        let text: String
        let symbolName: String
    }

    private(set) var nearby: [PetCard] = []
    private(set) var log: [Encounter] = []
    private(set) var isRunning = false
    private(set) var statusMessage: String?

    /// Called whenever a nearby pet does something our pet should react to.
    var onMessage: ((PetCard, PetMessage) -> Void)?
    /// Called only the first time a given pet introduces itself, so arriving can be made
    /// a great deal of while a routine card refresh passes quietly.
    var onArrival: ((PetCard) -> Void)?
    /// Called when a postcard arrives. Kept separate from `onMessage` because a postcard
    /// is for the feed rather than something the pet reacts to on the spot.
    var onPostcard: ((PetCard, PetPostEnvelope) -> Void)?
    /// Called when somebody likes a postcard, or takes a like back. For the feed rather
    /// than the pet — though the pet does hear about applause for its own postcard.
    var onLike: ((PetCard, PetMessage) -> Void)?
    /// Called for anything to do with groups: a code being held up, or a roster arriving.
    /// Bookkeeping between phones, which the pet has no opinion about.
    var onGroupMessage: ((PetCard, PetMessage) -> Void)?

    private var transport: NearbyTransport?
    private var pump: Task<Void, Never>?
    private var cardsByPeer: [String: PetCard] = [:]
    private var peersByCard: [String: String] = [:]
    private var myCard: PetCard?

    // MARK: Lifecycle

    func start(as card: PetCard) {
        myCard = card
        if isRunning {
            announce(card)
            return
        }

        let transport = NearbyTransport(localName: Self.serviceName(for: card))
        self.transport = transport
        pump = Task { [weak self] in
            for await event in transport.events {
                guard let self else { return }
                self.handle(event)
            }
        }
        transport.start()
        isRunning = true
        statusMessage = nil
    }

    func stop() {
        pump?.cancel()
        pump = nil
        transport?.stop()
        transport = nil
        isRunning = false
        nearby = []
        cardsByPeer = [:]
        peersByCard = [:]
    }

    /// Pushes a fresh card out to everyone already connected, e.g. after a mood change.
    func announce(_ card: PetCard) {
        myCard = card
        send(.hello(card), to: nil)
    }

    func send(_ message: PetMessage, to card: PetCard?) {
        guard let transport, let data = try? JSONEncoder().encode(message) else { return }
        transport.send(data, to: card.flatMap { peersByCard[$0.id] })
    }

    func note(_ text: String, symbolName: String = "sparkles") {
        log.insert(Encounter(date: .now, text: text, symbolName: symbolName), at: 0)
        if log.count > 40 { log.removeLast(log.count - 40) }
    }

    // MARK: Events

    private func handle(_ event: NearbyTransport.Event) {
        switch event {
        case .connected(let peer):
            guard let myCard,
                  let data = try? JSONEncoder().encode(PetMessage.hello(myCard))
            else { return }
            transport?.send(data, to: peer)

        case .disconnected(let peer):
            if let card = cardsByPeer.removeValue(forKey: peer) {
                peersByCard.removeValue(forKey: card.id)
                nearby.removeAll { $0.id == card.id }
                note("\(card.name) wandered out of range.", symbolName: "figure.walk.departure")
            }

        case .message(let peer, let payload):
            guard let message = try? JSONDecoder().decode(PetMessage.self, from: payload) else { return }
            receive(message, from: peer)

        case .failed(let reason):
            statusMessage = reason
        }
    }

    private func receive(_ message: PetMessage, from peer: String) {
        if case .hello(let card) = message {
            let isNew = cardsByPeer[peer] == nil
            cardsByPeer[peer] = card
            peersByCard[card.id] = peer
            if let index = nearby.firstIndex(where: { $0.id == card.id }) {
                nearby[index] = card
            } else {
                nearby.append(card)
            }
            if isNew {
                note("\(card.name) the \(card.kind.displayName.lowercased()) came over.",
                     symbolName: card.kind.symbolName)
            }
            onMessage?(card, message)
            if isNew {
                onArrival?(card)
            }
            return
        }

        guard let card = cardsByPeer[peer] else { return }

        // A postcard goes straight to the feed, and group traffic straight to the group
        // store. Neither is something the pet needs to have an opinion about.
        switch message {
        case .postcard(let envelope):
            onPostcard?(card, envelope)
        case .postcardLikes, .postcardUnlike:
            onLike?(card, message)
        case .groupProbe, .groupOffer, .groupSync:
            onGroupMessage?(card, message)
        default:
            onMessage?(card, message)
        }
    }

    // MARK: Helpers

    /// Bonjour service names must be unique on the network, so the pet's id is appended.
    fileprivate static func serviceName(for card: PetCard) -> String {
        "\(card.name.prefix(20))-\(card.id.suffix(6))"
    }

    /// The inverse of `serviceName(for:)`: the pet's name back out of an advertised
    /// service name. Nil for anything without the id suffix this app puts on the end.
    fileprivate nonisolated static func petName(fromServiceName serviceName: String) -> String? {
        guard let separator = serviceName.lastIndex(of: "-") else { return nil }
        let name = serviceName[serviceName.startIndex..<separator]
        return name.isEmpty ? nil : String(name)
    }
}

// MARK: - Name scout

/// Listens for the pets already on the network so the adoption flow can avoid suggesting
/// a name one of them answers to.
///
/// This only ever browses. A pet's name travels inside its Bonjour service name, so there
/// is nothing to dial and nothing to connect to — which matters here, because during
/// adoption there is no pet of our own to announce yet.
@Observable
final class NearbyNameScout {
    /// Lowercased names of every pet currently in range.
    private(set) var takenNames: Set<String> = []

    private var browser: NameBrowser?
    private var pump: Task<Void, Never>?

    /// Safe to call again while already looking.
    func start() {
        guard browser == nil else { return }
        let browser = NameBrowser()
        self.browser = browser
        pump = Task { [weak self] in
            for await names in browser.names {
                self?.takenNames = names
            }
        }
        browser.start()
    }

    func stop() {
        pump?.cancel()
        pump = nil
        browser?.stop()
        browser = nil
        takenNames = []
    }

    /// True when a pet in range already answers to this name.
    func isTaken(_ name: String) -> Bool {
        takenNames.contains(name.lowercased())
    }
}

/// A Bonjour browser and nothing else — no listener, so running one doesn't put a pet on
/// the network before there is a pet to put there.
///
/// Callbacks arrive on a private queue, so this lives outside the main actor and publishes
/// a plain `Sendable` set of names.
///
/// Unchecked: `browser` is only touched by `start()` and `stop()`, both called from the
/// main actor, and by `deinit`.
private nonisolated final class NameBrowser: @unchecked Sendable {
    let names: AsyncStream<Set<String>>

    private let continuation: AsyncStream<Set<String>>.Continuation
    private let queue = DispatchQueue(label: "PetPhone.nameScout")
    private var browser: NWBrowser?

    init() {
        let (stream, continuation) = AsyncStream.makeStream(of: Set<String>.self)
        self.names = stream
        self.continuation = continuation
    }

    deinit {
        browser?.cancel()
        continuation.finish()
    }

    func start() {
        let browser = NWBrowser(
            for: .bonjour(type: NearbyTransport.serviceType, domain: nil),
            using: NearbyTransport.makeParameters()
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.publish(results)
        }
        // A browse that never gets going simply finds nobody, which leaves every
        // suggestion on offer — exactly where the naming step starts from.
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        browser?.cancel()
        browser = nil
        continuation.finish()
    }

    private func publish(_ results: Set<NWBrowser.Result>) {
        var found: Set<String> = []
        for result in results {
            guard case .service(let serviceName, _, _, _) = result.endpoint,
                  let name = PetSocial.petName(fromServiceName: serviceName)
            else { continue }
            found.insert(name.lowercased())
        }
        continuation.yield(found)
    }
}

// MARK: - Transport

/// One live link to another phone, plus whatever bytes have arrived but not yet formed a
/// complete message.
///
/// Unchecked: `inbox` is only ever touched from the transport's serial queue, which is
/// also where every `NWConnection` callback is delivered.
private nonisolated final class PeerLink: @unchecked Sendable {
    let id: String
    let connection: NWConnection
    /// Bonjour name, when we were the side that dialled out.
    let serviceName: String?
    var inbox = Data()

    init(id: String, connection: NWConnection, serviceName: String?) {
        self.id = id
        self.connection = connection
        self.serviceName = serviceName
    }
}

/// Network framework plumbing: a Bonjour listener so other pets can find us, a browser so
/// we can find them, and length-prefixed JSON over TCP in between.
///
/// `includePeerToPeer` means two phones can do this with no Wi-Fi network at all.
/// Callbacks arrive on a private queue, so this type lives outside the main actor and
/// publishes plain `Sendable` events.
///
/// Unchecked: `links` and `dialled` are guarded by `lock`; `listener` and `browser` are
/// only touched by `start()`/`stop()`, which are called from the main actor.
private nonisolated final class NearbyTransport: @unchecked Sendable {
    enum Event: Sendable {
        case connected(peer: String)
        case disconnected(peer: String)
        case message(peer: String, payload: Data)
        case failed(String)
    }

    /// Must match an entry in the `NSBonjourServices` Info.plist array.
    static let serviceType = "_petphone._tcp"
    private static let maximumMessageBytes = 256 * 1024

    let events: AsyncStream<Event>

    private let continuation: AsyncStream<Event>.Continuation
    private let localName: String
    private let queue = DispatchQueue(label: "PetPhone.nearby")
    private let lock = NSLock()

    private var listener: NWListener?
    private var browser: NWBrowser?
    private var links: [String: PeerLink] = [:]
    /// Bonjour names we have already dialled, so a flapping browser doesn't pile up links.
    private var dialled: Set<String> = []

    init(localName: String) {
        let (stream, continuation) = AsyncStream.makeStream(of: Event.self)
        self.events = stream
        self.continuation = continuation
        self.localName = localName
    }

    fileprivate static func makeParameters() -> NWParameters {
        let parameters = NWParameters.tcp
        // The bit that makes two phones work on a train with no Wi-Fi.
        parameters.includePeerToPeer = true
        return parameters
    }

    func start() {
        do {
            let listener = try NWListener(using: Self.makeParameters())
            listener.service = NWListener.Service(name: localName, type: Self.serviceType)
            listener.newConnectionHandler = { [weak self] connection in
                self?.adopt(connection, serviceName: nil)
            }
            listener.stateUpdateHandler = { [weak self] state in
                if case .failed(let error) = state {
                    self?.continuation.yield(.failed("Couldn't announce your pet: \(error.localizedDescription)"))
                }
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            continuation.yield(.failed("Couldn't announce your pet: \(error.localizedDescription)"))
        }

        let browser = NWBrowser(
            for: .bonjour(type: Self.serviceType, domain: nil),
            using: Self.makeParameters()
        )
        browser.browseResultsChangedHandler = { [weak self] results, _ in
            self?.consider(results)
        }
        browser.stateUpdateHandler = { [weak self] state in
            if case .failed(let error) = state {
                self?.continuation.yield(.failed("Couldn't look for nearby pets: \(error.localizedDescription)"))
            }
        }
        browser.start(queue: queue)
        self.browser = browser
    }

    func stop() {
        listener?.cancel()
        listener = nil
        browser?.cancel()
        browser = nil

        lock.lock()
        let open = Array(links.values)
        links = [:]
        dialled = []
        lock.unlock()

        for link in open {
            link.connection.cancel()
        }
        continuation.finish()
    }

    /// Sends to one peer, or to everyone when `peer` is nil.
    func send(_ data: Data, to peer: String?) {
        let frame = Self.frame(data)

        lock.lock()
        let targets: [PeerLink]
        if let peer {
            targets = links[peer].map { [$0] } ?? []
        } else {
            targets = Array(links.values)
        }
        lock.unlock()

        for link in targets {
            link.connection.send(content: frame, completion: .contentProcessed { _ in })
        }
    }

    // MARK: Discovery

    private func consider(_ results: Set<NWBrowser.Result>) {
        for result in results {
            guard case .service(let name, _, _, _) = result.endpoint else { continue }
            // Exactly one side of a pair dials, otherwise both links get torn down.
            guard name > localName else { continue }

            lock.lock()
            let isNew = dialled.insert(name).inserted
            lock.unlock()
            guard isNew else { continue }

            let connection = NWConnection(to: result.endpoint, using: Self.makeParameters())
            adopt(connection, serviceName: name)
        }
    }

    private func adopt(_ connection: NWConnection, serviceName: String?) {
        let link = PeerLink(id: UUID().uuidString, connection: connection, serviceName: serviceName)

        lock.lock()
        links[link.id] = link
        lock.unlock()

        connection.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready:
                self.continuation.yield(.connected(peer: link.id))
                self.receiveNext(on: link)
            case .failed, .cancelled:
                self.drop(link)
            default:
                break
            }
        }
        connection.start(queue: queue)
    }

    private func drop(_ link: PeerLink) {
        lock.lock()
        let removed = links.removeValue(forKey: link.id)
        if let serviceName = link.serviceName {
            dialled.remove(serviceName)
        }
        lock.unlock()

        guard removed != nil else { return }
        link.connection.cancel()
        continuation.yield(.disconnected(peer: link.id))
    }

    // MARK: Framing
    //
    // TCP is a byte stream, so each message is prefixed with its length in four
    // big-endian bytes and reassembled on the way in.

    private static func frame(_ payload: Data) -> Data {
        let length = UInt32(payload.count)
        var frame = Data(capacity: payload.count + 4)
        frame.append(UInt8((length >> 24) & 0xFF))
        frame.append(UInt8((length >> 16) & 0xFF))
        frame.append(UInt8((length >> 8) & 0xFF))
        frame.append(UInt8(length & 0xFF))
        frame.append(payload)
        return frame
    }

    private func receiveNext(on link: PeerLink) {
        link.connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) {
            [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data, !data.isEmpty {
                self.ingest(data, into: link)
            }
            if isComplete || error != nil {
                self.drop(link)
                return
            }
            self.receiveNext(on: link)
        }
    }

    /// Runs on the transport's serial queue, so the inbox needs no extra locking.
    private func ingest(_ data: Data, into link: PeerLink) {
        link.inbox.append(data)

        while link.inbox.count >= 4 {
            let header = [UInt8](link.inbox.prefix(4))
            let length = Int(header[0]) << 24 | Int(header[1]) << 16 | Int(header[2]) << 8 | Int(header[3])

            guard length > 0, length <= Self.maximumMessageBytes else {
                // Garbled stream; nothing sensible left to read.
                drop(link)
                return
            }
            guard link.inbox.count >= 4 + length else { return }

            let payload = Data(link.inbox.dropFirst(4).prefix(length))
            link.inbox = Data(link.inbox.dropFirst(4 + length))
            continuation.yield(.message(peer: link.id, payload: payload))
        }
    }
}
