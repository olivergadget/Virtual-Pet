import Foundation
import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Where the pet sticker sits on a photo. Unit coordinates, so the sticker lands in the
/// same spot whether the postcard is being drawn thumbnail-sized or full screen.
struct StickerPlacement: Codable, Sendable, Equatable {
    /// Across the photo: 0 at the left edge, 1 at the right.
    var x: Double
    /// Down the photo: 0 at the top, 1 at the bottom.
    var y: Double
    /// Multiplier on the sticker's natural size, which is a little under half the
    /// photo's width.
    var scale: Double
    var rotation: Double
    /// Mirrors the pet, so it can be turned to look into the photo rather than out of it.
    var isFlipped: Bool

    init(
        x: Double = 0.5,
        y: Double = 0.74,
        scale: Double = 1,
        rotation: Double = 0,
        isFlipped: Bool = false
    ) {
        self.x = x
        self.y = y
        self.scale = scale
        self.rotation = rotation
        self.isFlipped = isFlipped
    }

    // Decoded defensively, like everything else that travels between builds: a postcard
    // with a plainly-placed sticker beats a postcard that won't open.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        x = try container.decodeIfPresent(Double.self, forKey: .x) ?? 0.5
        y = try container.decodeIfPresent(Double.self, forKey: .y) ?? 0.74
        scale = try container.decodeIfPresent(Double.self, forKey: .scale) ?? 1
        rotation = try container.decodeIfPresent(Double.self, forKey: .rotation) ?? 0
        isFlipped = try container.decodeIfPresent(Bool.self, forKey: .isFlipped) ?? false
    }

    /// Where the pet starts out on a written note: low and centred, under the writing,
    /// and a shade smaller than it sits on a photo so the words have room.
    static let onNote = StickerPlacement(x: 0.5, y: 0.76, scale: 0.9)

    /// Keeps the sticker's middle on the photo however hard it is dragged about, and
    /// stops it being pinched down to a speck or up past the edges of the frame.
    mutating func clamp() {
        x = min(max(x, 0.08), 0.92)
        y = min(max(y, 0.08), 0.92)
        scale = min(max(scale, 0.45), 2.4)
    }
}

/// One thing somebody put out for whoever happens to be nearby — a photo, or just a few
/// words if they'd rather — with their pet stuck on the front of it.
///
/// The sticker is never burnt into the photo. Only its placement travels, and the pet is
/// redrawn from shapes on whichever phone is looking at the postcard — so a postcard from
/// across the room has a creature on it that breathes and blinks like your own.
struct PetPost: Codable, Identifiable, Sendable, Equatable {
    var id: String
    /// The pet that made it, so the feed can tell your own postcards from everyone else's.
    var authorPetID: String
    var authorName: String
    var kind: PetKind
    var appearance: PetAppearance
    /// The author's mood score when they posted, 0...1, so the sticker wears the face the
    /// pet actually had at the time.
    var mood: Double
    var caption: String
    /// False for a written note — a postcard whose front is nothing but its words.
    ///
    /// Worth storing rather than working out from whether a photo turned up, because a
    /// note and a photo that went missing are two very different things to show.
    var hasPhoto: Bool
    var createdAt: Date
    var sticker: StickerPlacement
    /// The group this was posted to, or nil for the open nearby feed. A postcard with a
    /// group on it is only ever sent to that group's members, and is only ever let in by
    /// a phone that is in the group too.
    var groupID: String?
    /// Rounded to roughly a hundred metres before it ever leaves the phone, and nil when
    /// location is switched off.
    var latitude: Double?
    var longitude: Double?

    init(
        id: String = UUID().uuidString,
        authorPetID: String,
        authorName: String,
        kind: PetKind,
        appearance: PetAppearance,
        mood: Double,
        caption: String,
        hasPhoto: Bool = true,
        createdAt: Date = .now,
        sticker: StickerPlacement = StickerPlacement(),
        groupID: String? = nil,
        latitude: Double? = nil,
        longitude: Double? = nil
    ) {
        self.id = id
        self.authorPetID = authorPetID
        self.authorName = authorName
        self.kind = kind
        self.appearance = appearance
        self.mood = mood
        self.caption = caption
        self.hasPhoto = hasPhoto
        self.createdAt = createdAt
        self.sticker = sticker
        self.groupID = groupID
        self.latitude = latitude
        self.longitude = longitude
    }

    // Decoded defensively. This one arrives over the air from a phone that may be running
    // a different build of the app, so nothing here is assumed to be present.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
        authorPetID = try container.decodeIfPresent(String.self, forKey: .authorPetID) ?? ""
        authorName = try container.decodeIfPresent(String.self, forKey: .authorName) ?? "Someone's pet"
        kind = try container.decodeIfPresent(PetKind.self, forKey: .kind) ?? .cat
        appearance = try container.decodeIfPresent(PetAppearance.self, forKey: .appearance) ?? PetAppearance()
        mood = try container.decodeIfPresent(Double.self, forKey: .mood) ?? 0.7
        caption = try container.decodeIfPresent(String.self, forKey: .caption) ?? ""
        // Postcards made before notes existed always had a photo on the front, so a
        // missing flag means there is one to look for.
        hasPhoto = try container.decodeIfPresent(Bool.self, forKey: .hasPhoto) ?? true
        createdAt = try container.decodeIfPresent(Date.self, forKey: .createdAt) ?? .now
        sticker = try container.decodeIfPresent(StickerPlacement.self, forKey: .sticker) ?? StickerPlacement()
        groupID = try container.decodeIfPresent(String.self, forKey: .groupID)
        latitude = try container.decodeIfPresent(Double.self, forKey: .latitude)
        longitude = try container.decodeIfPresent(Double.self, forKey: .longitude)
    }
}

extension PetPost {
    /// The longest a caption is allowed to be. Long enough for a joke, short enough that
    /// it never covers the photo it is supposed to be describing.
    static let captionLimit = 90

    /// The longest a written note is allowed to be. Roomier than a caption, because with
    /// no photo behind it the writing is the whole postcard rather than a remark about
    /// one — but still short enough to read at a glance and to fit on the card.
    static let noteLimit = 200

    /// True for a postcard somebody typed instead of photographing.
    var isNote: Bool { !hasPhoto }

    /// A stand-in pet, so ``PetFaceView`` can draw the author's creature on a phone that
    /// has never met it.
    ///
    /// All four needs are set to the mood the author posted with, which — because the
    /// mood is a weighted blend of exactly those four — reproduces that mood score
    /// precisely. The floor of 0.2 is where ``Pet/moodScore`` starts penalising a badly
    /// neglected need, and going below it would drag the face further down than the
    /// postcard ever claimed.
    var stickerPet: Pet {
        var stand = Pet(name: authorName, kind: kind, appearance: appearance, now: createdAt)
        let level = min(max(mood, 0.2), 1)
        stand.needs = Needs(fullness: level, fun: level, affection: level, rest: level)
        return stand
    }

    var moodAtPosting: Mood { stickerPet.mood }

    /// Rounds a fix down to about a hundred metres. Postcards are handed over by phones
    /// that were within radio range anyway, so there is nothing to gain from sending a
    /// precise position along with one.
    static func coarse(_ degrees: Double) -> Double {
        (degrees * 1_000).rounded() / 1_000
    }
}

// MARK: - Likes

/// Somebody nearby saying they liked a postcard.
///
/// A like is a small fact of its own rather than a field on the postcard, because the
/// postcard belongs to its author and the like doesn't. It is only ever sent by the phone
/// that gave it, kept in a file beside the feed, and thrown away with the postcard it
/// belongs to.
struct PostLike: Codable, Identifiable, Sendable, Equatable {
    /// The postcard this is a like for.
    var postID: String
    /// The pet that liked it — which is also the only phone the like is trusted from.
    var petID: String
    var petName: String
    var kind: PetKind
    var likedAt: Date

    /// One like per pet per postcard, so the pair of ids is the whole identity.
    var id: String { "\(postID)|\(petID)" }

    init(postID: String, pet: Pet, likedAt: Date = .now) {
        self.postID = postID
        self.petID = pet.id.uuidString
        self.petName = pet.name
        self.kind = pet.kind
        self.likedAt = likedAt
    }

    // Decoded defensively. Like a postcard, this arrives from a phone that may be running
    // a different build of the app.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        postID = try container.decodeIfPresent(String.self, forKey: .postID) ?? ""
        petID = try container.decodeIfPresent(String.self, forKey: .petID) ?? ""
        petName = try container.decodeIfPresent(String.self, forKey: .petName) ?? "Someone's pet"
        kind = try container.decodeIfPresent(PetKind.self, forKey: .kind) ?? .cat
        likedAt = try container.decodeIfPresent(Date.self, forKey: .likedAt) ?? .now
    }

    /// False for a like that can't be pinned to a postcard or to a pet, which is the only
    /// way either id comes back empty.
    var isUsable: Bool { !postID.isEmpty && !petID.isEmpty }
}

/// A postcard with its photo attached, which is the shape one travels between phones in.
///
/// Photos live in their own files on disk rather than inside the feed's JSON, so this
/// wrapper exists only for the trip over the wire.
struct PetPostEnvelope: Codable, Sendable {
    var post: PetPost
    /// Empty for a written note, which has nothing to carry. That also means a phone
    /// running a build from before notes existed quietly refuses one, rather than
    /// showing a card it has no idea how to draw.
    var imageData: Data
}

// MARK: - Storage

/// Postcards on disk: the details in one JSON file, each photo in its own JPEG beside it.
///
/// The photos are deliberately kept out of the JSON. A feed of sixty base64-encoded
/// images would be several megabytes to parse at launch, and the pictures are only ever
/// wanted one at a time as they scroll past.
enum PostArchive {
    private static let fileName = "posts.json"
    /// Likes for every postcard, in one small file. They are kept apart from the postcards
    /// because a like arrives long after the postcard it belongs to, from somebody else
    /// entirely — rewriting the whole feed to record one would be a strange way round.
    private static let likesFileName = "likes.json"
    /// How many postcards are kept. The oldest fall off the end, photo and all.
    static let maximumPosts = 60

    /// The shared container when the App Group is available, falling back to the app's
    /// own Application Support folder — the same arrangement ``PetArchive`` uses.
    private static var folder: URL? {
        let shared = FileManager.default
            .containerURL(forSecurityApplicationGroupIdentifier: PetArchive.appGroupIdentifier)
        let base = shared ?? (try? FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        ))
        guard let base else { return nil }
        let folder = base.appendingPathComponent("PetPhone/Postcards", isDirectory: true)
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        return folder
    }

    private static var indexURL: URL? {
        folder?.appendingPathComponent(fileName)
    }

    /// Newest first, which is the order the feed scrolls in.
    static func load() -> [PetPost] {
        guard let indexURL, let data = try? Data(contentsOf: indexURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        guard let posts = try? decoder.decode([PetPost].self, from: data) else { return [] }
        return posts.sorted { $0.createdAt > $1.createdAt }
    }

    static func save(_ posts: [PetPost]) {
        guard let indexURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(posts) else { return }
        try? data.write(to: indexURL, options: .atomic)
    }

    private static var likesURL: URL? {
        folder?.appendingPathComponent(likesFileName)
    }

    static func loadLikes() -> [PostLike] {
        guard let likesURL, let data = try? Data(contentsOf: likesURL) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return (try? decoder.decode([PostLike].self, from: data)) ?? []
    }

    static func saveLikes(_ likes: [PostLike]) {
        guard let likesURL else { return }
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(likes) else { return }
        try? data.write(to: likesURL, options: .atomic)
    }

    static func imageURL(forPost id: String) -> URL? {
        // Ids are generated as UUIDs, but one arriving from another phone is only as
        // trustworthy as that phone — so it is never allowed to become a path of its own.
        let safe = id.filter { $0.isLetter || $0.isNumber || $0 == "-" }
        guard !safe.isEmpty else { return nil }
        return folder?.appendingPathComponent("\(safe).jpg")
    }

    /// Returns false when the photo couldn't be written, in which case the postcard is
    /// not worth keeping either.
    static func writeImage(_ data: Data, forPost id: String) -> Bool {
        guard let url = imageURL(forPost: id) else { return false }
        do {
            try data.write(to: url, options: .atomic)
            return true
        } catch {
            return false
        }
    }

    static func readImage(forPost id: String) -> Data? {
        guard let url = imageURL(forPost: id) else { return nil }
        return try? Data(contentsOf: url)
    }

    static func removeImage(forPost id: String) {
        guard let url = imageURL(forPost: id) else { return }
        try? FileManager.default.removeItem(at: url)
    }

    static func erase() {
        guard let folder else { return }
        try? FileManager.default.removeItem(at: folder)
    }
}

// MARK: - Photos

#if canImport(UIKit)
/// Turning a camera frame into bytes small enough to hand to another phone.
enum PostImage {
    /// The longest side a posted photo is kept at. A postcard is only ever looked at on a
    /// phone screen, so anything larger is bytes nobody sees.
    static let maximumEdge: CGFloat = 1_280
    /// One message on the nearby transport tops out at 256 KB, and the postcard's details
    /// and base64 overhead ride along with the photo, so the picture itself has to leave
    /// comfortable room.
    static let maximumBytes = 150 * 1_024

    /// Downscales, then drops quality a step at a time until the photo fits inside a
    /// single message.
    static func encode(_ image: UIImage) -> Data? {
        let scaled = downscaled(image)
        for quality in [0.7, 0.55, 0.4, 0.28, 0.18] as [CGFloat] {
            guard let data = scaled.jpegData(compressionQuality: quality) else { continue }
            if data.count <= maximumBytes { return data }
        }
        // Grainy but sendable beats pristine and stuck on this phone.
        return scaled.jpegData(compressionQuality: 0.1)
    }

    private static func downscaled(_ image: UIImage) -> UIImage {
        let longest = max(image.size.width, image.size.height)
        guard longest > maximumEdge, longest > 0 else { return image }
        let ratio = maximumEdge / longest
        let target = CGSize(
            width: (image.size.width * ratio).rounded(),
            height: (image.size.height * ratio).rounded()
        )

        let format = UIGraphicsImageRendererFormat.default()
        // A photo has no transparency to preserve, and scale 1 keeps the pixel count at
        // exactly what was asked for rather than two or three times it.
        format.scale = 1
        format.opaque = true
        return UIGraphicsImageRenderer(size: target, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: target))
        }
    }
}
#endif
