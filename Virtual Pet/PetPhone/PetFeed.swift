import CoreLocation
import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Which postcards the feed is showing.
enum FeedScope: Hashable {
    /// The open feed: everybody in range, and no group attached.
    case nearby
    case group(String)

    var groupID: String? {
        if case .group(let id) = self { return id }
        return nil
    }
}

/// The Out & About feed: postcards this phone has made, and postcards handed over by
/// other phones that came within range.
///
/// There is no server anywhere in this app. A postcard reaches you because its author's
/// phone was close enough to pass it across, which is what makes the feed a local one —
/// it is the people who have actually been near you, not a list of strangers.
///
/// The feed knows nothing about groups. Whether a given postcard may go to, or come
/// from, a given phone is decided by ``canSend`` and ``accepts``, which ``PetWorld``
/// fills in from the group rosters.
@Observable
final class PetFeed {
    private(set) var posts: [PetPost] = []
    /// Who liked what, keyed by postcard id.
    ///
    /// Each phone's count is the likes it has actually been handed, which for a feed with
    /// no server in it is the only count there is: a like reaches you because the phone
    /// that gave it came within range of yours. So two people looking at the same
    /// postcard may honestly see different numbers.
    private(set) var likes: [String: [PostLike]] = [:]
    /// Set when something couldn't be saved or sent, so a screen can say so plainly.
    private(set) var statusMessage: String?

    /// Puts a message out over the nearby transport. Wired up by ``PetWorld``, so the
    /// feed needs to know nothing about Bonjour.
    var send: ((PetMessage, PetCard) -> Void)?
    /// Who is in range at the moment.
    var nearby: () -> [PetCard] = { [] }
    /// Whether one of our postcards may be handed to a particular phone. A postcard with
    /// a group on it may only go to that group's members.
    var canSend: ((PetPost, PetCard) -> Bool)?
    /// Whether an arriving postcard is one to keep.
    var accepts: ((PetPost, PetCard) -> Bool)?

    /// How many of your own postcards a newly arrived phone is handed. Enough to make
    /// their feed worth scrolling, few enough that meeting somebody isn't a flood.
    private static let postcardsSharedOnArrival = 3
    /// Decoded photos, kept to a handful. Sixty full-size images in memory at once would
    /// be a great deal of RAM for a feed that only shows one at a time.
    private static let cachedImageLimit = 12

    #if canImport(UIKit)
    // Ignored by observation on purpose. A view asking for a photo also warms the cache,
    // and if that counted as a change the view would invalidate itself every time it
    // drew — which is a redraw loop, not a feed.
    @ObservationIgnored private var imageCache: [String: UIImage] = [:]
    /// Least recently used first, so the cache knows what to throw away.
    @ObservationIgnored private var cacheOrder: [String] = []
    #endif

    // MARK: Lifecycle

    func load() {
        guard posts.isEmpty else { return }
        posts = PostArchive.load()
        likes = Self.grouped(PostArchive.loadLikes(), amongst: posts)
    }

    /// Everything goes when the pet does — the postcards were theirs.
    func erase() {
        posts = []
        likes = [:]
        statusMessage = nil
        #if canImport(UIKit)
        imageCache = [:]
        cacheOrder = []
        #endif
        PostArchive.erase()
    }

    func isMine(_ post: PetPost, pet: Pet?) -> Bool {
        guard let pet else { return false }
        return post.authorPetID == pet.id.uuidString
    }

    /// What the feed shows for a given scope. A group postcard never appears in the open
    /// feed, and vice versa.
    func posts(in scope: FeedScope) -> [PetPost] {
        posts.filter { $0.groupID == scope.groupID }
    }

    /// Dropped when a group is left, so its postcards go with it.
    func removePosts(inGroup groupID: String) {
        let doomed = posts.filter { $0.groupID == groupID }
        guard !doomed.isEmpty else { return }
        for post in doomed { forget(post) }
        posts.removeAll { $0.groupID == groupID }
        PostArchive.save(posts)
        persistLikes()
    }

    // MARK: Posting

    #if canImport(UIKit)
    /// Saves a postcard and hands it to whoever is entitled to it.
    ///
    /// A nil photo makes it a written note, where the caption is the front of the card
    /// instead of a remark under a picture. Returns nil when there was nothing to post
    /// or the photo couldn't be written, in which case nothing is added to the feed and
    /// `statusMessage` explains why.
    @discardableResult
    func post(
        photo: UIImage?,
        caption: String,
        sticker: StickerPlacement,
        groupID: String?,
        pet: Pet,
        coordinate: CLLocationCoordinate2D?
    ) -> PetPost? {
        var imageData: Data?
        if let photo {
            guard let encoded = PostImage.encode(photo) else {
                statusMessage = "That photo couldn't be prepared. Try taking another."
                return nil
            }
            imageData = encoded
        }

        let words = caption.trimmingCharacters(in: .whitespacesAndNewlines)
        // A note with nothing written on it is a blank card. A photo can go out without
        // a caption, but this can't.
        guard imageData != nil || !words.isEmpty else {
            statusMessage = "Write something first."
            return nil
        }

        let post = PetPost(
            authorPetID: pet.id.uuidString,
            authorName: pet.name,
            kind: pet.kind,
            appearance: pet.appearance,
            mood: pet.moodScore,
            caption: words,
            hasPhoto: imageData != nil,
            sticker: sticker,
            groupID: groupID,
            latitude: coordinate.map { PetPost.coarse($0.latitude) },
            longitude: coordinate.map { PetPost.coarse($0.longitude) }
        )

        if let imageData {
            guard PostArchive.writeImage(imageData, forPost: post.id) else {
                statusMessage = "There wasn't room to save that photo."
                return nil
            }
        }

        statusMessage = nil
        if let photo { cache(photo, forPost: post.id) }
        insert(post)
        // Anyone entitled to it and in range gets it now; anyone else when they turn up.
        deliver(PetPostEnvelope(post: post, imageData: imageData ?? Data()))
        return post
    }
    #endif

    /// Takes a postcard down. Only ever used on your own, from the feed.
    func remove(_ post: PetPost) {
        posts.removeAll { $0.id == post.id }
        forget(post)
        PostArchive.save(posts)
        persistLikes()
    }

    // MARK: Likes

    /// Who liked a postcard, most recent first.
    func likes(for post: PetPost) -> [PostLike] {
        (likes[post.id] ?? []).sorted { $0.likedAt > $1.likedAt }
    }

    func likeCount(for post: PetPost) -> Int {
        likes[post.id]?.count ?? 0
    }

    func hasLiked(_ post: PetPost, pet: Pet?) -> Bool {
        guard let pet else { return false }
        return likes[post.id]?.contains { $0.petID == pet.id.uuidString } == true
    }

    /// Likes or unlikes a postcard and tells everyone in range who is entitled to it.
    /// Returns whether the postcard has ended up liked.
    ///
    /// Anybody who isn't in range hears about it the next time they are — see
    /// ``shareLikes(with:from:)``.
    @discardableResult
    func toggleLike(on post: PetPost, by pet: Pet) -> Bool {
        // Liking a postcard that has just fallen off the end of the feed would leave a
        // like with nothing to belong to.
        guard let post = posts.first(where: { $0.id == post.id }) else { return false }
        let petID = pet.id.uuidString

        if let index = likes[post.id]?.firstIndex(where: { $0.petID == petID }) {
            likes[post.id]?.remove(at: index)
            if likes[post.id]?.isEmpty == true { likes[post.id] = nil }
            persistLikes()
            tell(.postcardUnlike(postID: post.id, petID: petID), about: post)
            return false
        }

        let like = PostLike(postID: post.id, pet: pet)
        likes[post.id, default: []].append(like)
        persistLikes()
        tell(.postcardLikes([like]), about: post)
        return true
    }

    /// Likes arriving from another phone: one somebody has just given, or their back
    /// catalogue as they come into range.
    ///
    /// Returns the ones that were actually new, so the pet can be told when the applause
    /// was for a postcard of yours.
    @discardableResult
    func receiveLikes(_ incoming: [PostLike], from card: PetCard) -> [PostLike] {
        var landed: [PostLike] = []

        for like in incoming where like.isUsable {
            // A phone can only speak for its own pet, exactly as with a postcard.
            // Believing the pet field would let any peer like things as anybody, you
            // included.
            guard like.petID == card.id else { continue }
            // Only postcards we have, and only ones this phone was entitled to see —
            // which for a group postcard means we and the liker are both in the group.
            guard let post = posts.first(where: { $0.id == like.postID }) else { continue }
            guard accepts?(post, card) ?? (post.groupID == nil) else { continue }
            guard likes[post.id]?.contains(where: { $0.petID == like.petID }) != true else { continue }
            likes[post.id, default: []].append(like)
            landed.append(like)
        }

        guard !landed.isEmpty else { return [] }
        persistLikes()
        return landed
    }

    /// Somebody has taken their like back. Trusted on the same terms it was given on:
    /// only from the phone whose pet gave it.
    func receiveUnlike(postID: String, petID: String, from card: PetCard) {
        guard petID == card.id else { return }
        guard let index = likes[postID]?.firstIndex(where: { $0.petID == petID }) else { return }
        likes[postID]?.remove(at: index)
        if likes[postID]?.isEmpty == true { likes[postID] = nil }
        persistLikes()
    }

    /// Hands a phone that has just turned up our own likes for the postcards it is
    /// entitled to, so one given while they were out of range still reaches them.
    ///
    /// Only our own. A like is only ever trusted from the phone that gave it, so passing
    /// on somebody else's would gain nothing and leave plenty of room for mischief.
    func shareLikes(with card: PetCard, from pet: Pet?) {
        guard let pet else { return }
        let petID = pet.id.uuidString
        let mine = posts.compactMap { post -> PostLike? in
            guard canSend?(post, card) ?? (post.groupID == nil) else { return nil }
            return likes[post.id]?.first { $0.petID == petID }
        }
        guard !mine.isEmpty else { return }
        // Small enough to go in one message even at the feed's full sixty postcards.
        send?(.postcardLikes(mine), card)
    }

    // MARK: Nearby

    /// A postcard has arrived from another phone.
    func receive(_ envelope: PetPostEnvelope, from card: PetCard) {
        let post = envelope.post
        // A phone can only speak for its own pet. Believing the author field would let
        // any peer post as anybody, including as you.
        guard post.authorPetID == card.id else { return }
        // A group postcard is only let in if we and the sender are both in that group.
        guard accepts?(post, card) ?? (post.groupID == nil) else { return }
        guard !posts.contains(where: { $0.id == post.id }) else { return }

        if post.hasPhoto {
            guard !envelope.imageData.isEmpty,
                  envelope.imageData.count <= PostImage.maximumBytes * 2 else { return }
            guard PostArchive.writeImage(envelope.imageData, forPost: post.id) else { return }
        } else {
            // A note is its words and nothing else, so one that arrives blank is a
            // card with no front to it.
            guard !post.caption.isEmpty else { return }
        }

        insert(post)
    }

    /// Hands a phone that has just turned up your most recent postcards, so their feed
    /// has something in it the moment they walk in. Only the ones they are entitled to.
    ///
    /// Each goes as its own message: one frame on the transport is capped, and three
    /// photos in a single message would sail straight past that cap.
    func sharePostcards(with card: PetCard, from pet: Pet?) {
        let mine = posts
            .filter { isMine($0, pet: pet) && (canSend?($0, card) ?? ($0.groupID == nil)) }
            .prefix(Self.postcardsSharedOnArrival)
        guard !mine.isEmpty else { return }

        for (index, post) in mine.enumerated() {
            let imageData = PostArchive.readImage(forPost: post.id)
            // A note has no photo to find; a photo postcard whose file has gone isn't
            // worth sending as an empty card.
            guard !post.hasPhoto || imageData != nil else { continue }
            let envelope = PetPostEnvelope(post: post, imageData: imageData ?? Data())
            guard index > 0 else {
                send?(.postcard(envelope), card)
                continue
            }
            // Staggered, so a link that has only just come up isn't handed three photos
            // in the same instant.
            Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(400 * index))
                self?.send?(.postcard(envelope), card)
            }
        }
    }

    /// Sends a postcard to every phone in range that is allowed to have it.
    private func deliver(_ envelope: PetPostEnvelope) {
        tell(.postcard(envelope), about: envelope.post)
    }

    /// Sends something about a postcard — the postcard itself, or a like for it — to every
    /// phone in range that is entitled to the postcard.
    private func tell(_ message: PetMessage, about post: PetPost) {
        for card in nearby() where canSend?(post, card) ?? (post.groupID == nil) {
            send?(message, card)
        }
    }

    // MARK: Photos

    #if canImport(UIKit)
    /// The photo for a postcard, read from disk the first time and cached after that.
    /// Nil for a written note, which never had one.
    func image(for post: PetPost) -> UIImage? {
        guard post.hasPhoto else { return nil }
        if let cached = imageCache[post.id] {
            touch(post.id)
            return cached
        }
        guard let data = PostArchive.readImage(forPost: post.id),
              let image = UIImage(data: data)
        else { return nil }
        cache(image, forPost: post.id)
        return image
    }

    private func cache(_ image: UIImage, forPost id: String) {
        imageCache[id] = image
        touch(id)
        while cacheOrder.count > Self.cachedImageLimit {
            let oldest = cacheOrder.removeFirst()
            imageCache.removeValue(forKey: oldest)
        }
    }

    private func touch(_ id: String) {
        cacheOrder.removeAll { $0 == id }
        cacheOrder.append(id)
    }
    #endif

    /// Drops a postcard's photo from disk and from memory, and its likes with it. Leaves
    /// `posts` alone, so the caller can decide how to take it out of the list — and is
    /// left to call ``persistLikes()`` once it has finished.
    private func forget(_ post: PetPost) {
        PostArchive.removeImage(forPost: post.id)
        likes.removeValue(forKey: post.id)
        #if canImport(UIKit)
        imageCache.removeValue(forKey: post.id)
        cacheOrder.removeAll { $0 == post.id }
        #endif
    }

    // MARK: Helpers

    private func persistLikes() {
        PostArchive.saveLikes(likes.values.flatMap { $0 })
    }

    /// Likes indexed by postcard, with anything belonging to a postcard that is no longer
    /// in the feed — or naming the same pet twice — left out.
    private static func grouped(
        _ likes: [PostLike],
        amongst posts: [PetPost]
    ) -> [String: [PostLike]] {
        let known = Set(posts.map(\.id))
        var grouped: [String: [PostLike]] = [:]
        for like in likes where like.isUsable && known.contains(like.postID) {
            guard grouped[like.postID]?.contains(where: { $0.petID == like.petID }) != true
            else { continue }
            grouped[like.postID, default: []].append(like)
        }
        return grouped
    }

    /// Newest first, trimmed to the cap, saved.
    private func insert(_ post: PetPost) {
        posts.append(post)
        posts.sort { $0.createdAt > $1.createdAt }
        if posts.count > PostArchive.maximumPosts {
            for dropped in posts[PostArchive.maximumPosts...] {
                forget(dropped)
            }
            posts.removeLast(posts.count - PostArchive.maximumPosts)
            persistLikes()
        }
        PostArchive.save(posts)
    }

    /// How far away a postcard was made, as something worth reading. Nil when either end
    /// of the sum is missing, which is most of the time with location switched off.
    func distanceDescription(of post: PetPost, from coordinate: CLLocationCoordinate2D?) -> String? {
        guard let coordinate,
              let latitude = post.latitude,
              let longitude = post.longitude
        else { return nil }

        let there = CLLocation(latitude: latitude, longitude: longitude)
        let here = CLLocation(latitude: coordinate.latitude, longitude: coordinate.longitude)
        let metres = here.distance(from: there)

        // Both ends are rounded to about a hundred metres, so anything under that is
        // "right here" rather than a number pretending to be precise.
        switch metres {
        case ..<150:
            return "Right here"
        case ..<950:
            return "\(Int((metres / 100).rounded()) * 100) m away"
        case ..<30_000:
            return String(format: "%.1f km away", metres / 1_000)
        default:
            return String(format: "%.0f km away", metres / 1_000)
        }
    }
}
