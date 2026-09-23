import SwiftUI

/// The species someone can adopt. Each kind carries its own silhouette, palette and voice,
/// so swapping species changes how the phone looks *and* how it sounds.
enum PetKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case cat
    case dog
    case bunny
    case dragon
    case monkey

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cat: "Cat"
        case .dog: "Dog"
        case .bunny: "Bunny"
        case .dragon: "Dragon"
        case .monkey: "Monkey"
        }
    }

    var tagline: String {
        switch self {
        case .cat: "Purrs in your palm. Judges you from the table."
        case .dog: "Will absolutely tell the neighbours you left."
        case .bunny: "Small, twitchy, thumps when ignored."
        case .dragon: "Hoards your battery. Rumbles like a furnace."
        case .monkey: "Steals things. Hands them back for a price."
        }
    }

    var symbolName: String {
        switch self {
        case .cat: "cat.fill"
        case .dog: "dog.fill"
        case .bunny: "hare.fill"
        case .dragon: "lizard.fill"
        // There is no monkey in SF Symbols; the teddy bear is the closest thing
        // with the right animal silhouette.
        case .monkey: "teddybear.fill"
        }
    }

    var suggestedNames: [String] {
        switch self {
        case .cat: ["Mochi", "Biscuit", "Noodle", "Pixel"]
        case .dog: ["Rufus", "Waffle", "Bolt", "Pepper"]
        case .bunny: ["Clover", "Bean", "Nibbles", "Sprout"]
        case .dragon: ["Ember", "Cinder", "Toast", "Basil"]
        case .monkey: ["Bongo", "Mango", "Cheeko", "Nutmeg"]
        }
    }

    var favouriteFood: String {
        switch self {
        case .cat: "a tin of tuna"
        case .dog: "a strip of jerky"
        case .bunny: "a fistful of greens"
        case .dragon: "one (1) charcoal briquette"
        case .monkey: "a slightly bruised banana"
        }
    }

    /// What this species will chase around the screen during a play session.
    var toySymbol: String {
        switch self {
        case .cat: "circle.fill"
        case .dog: "tennisball.fill"
        case .bunny: "leaf.fill"
        case .dragon: "flame.fill"
        case .monkey: "bell.fill"
        }
    }

    var toyName: String {
        switch self {
        case .cat: "laser dot"
        case .dog: "tennis ball"
        case .bunny: "leaf"
        case .dragon: "spark"
        case .monkey: "jingle bell"
        }
    }

    var toyColor: Color {
        switch self {
        case .cat: Color(red: 0.98, green: 0.18, blue: 0.22)
        case .dog: Color(red: 0.80, green: 0.90, blue: 0.25)
        case .bunny: Color(red: 0.35, green: 0.76, blue: 0.42)
        case .dragon: Color(red: 1.00, green: 0.58, blue: 0.15)
        case .monkey: Color(red: 0.96, green: 0.78, blue: 0.20)
        }
    }

    /// The colour of whatever goes in the bowl at feeding time.
    var foodColor: Color {
        switch self {
        case .cat: Color(red: 0.80, green: 0.47, blue: 0.38)
        case .dog: Color(red: 0.56, green: 0.36, blue: 0.22)
        case .bunny: Color(red: 0.42, green: 0.66, blue: 0.32)
        case .dragon: Color(red: 0.28, green: 0.28, blue: 0.32)
        case .monkey: Color(red: 0.94, green: 0.84, blue: 0.38)
        }
    }

    var earStyle: EarStyle {
        switch self {
        case .cat: .pointed
        case .dog: .floppy
        case .bunny: .tall
        case .dragon: .horned
        case .monkey: .round
        }
    }

    /// True for species that can actually purr. Dogs get a contented groan instead, and
    /// a happy monkey chatters.
    var canPurr: Bool {
        switch self {
        case .cat, .bunny, .dragon: true
        case .dog, .monkey: false
        }
    }

    /// Noses are pink on the soft species and near-black on the others; using the accent
    /// colour everywhere left the dog with a bright blue nose. Takes the accent rather
    /// than reading it back off the species, so a recoloured pet gets a matching nose.
    func noseColor(accent: Color) -> Color {
        switch self {
        case .cat, .bunny: accent
        case .dog: Color(red: 0.22, green: 0.16, blue: 0.13)
        case .dragon: Color(red: 0.16, green: 0.24, blue: 0.21)
        case .monkey: Color(red: 0.30, green: 0.20, blue: 0.16)
        }
    }

    /// The species' stock colours, before anything the owner changed in the designer.
    var colors: PetColorScheme {
        switch self {
        case .cat:
            PetColorScheme(
                coat: PetColor(0.97, 0.74, 0.44),
                shade: PetColor(0.87, 0.58, 0.30),
                belly: PetColor(0.99, 0.94, 0.86),
                accent: PetColor(0.95, 0.55, 0.62),
                sky: [PetColor(0.99, 0.87, 0.74), PetColor(0.97, 0.69, 0.63)]
            )
        case .dog:
            PetColorScheme(
                coat: PetColor(0.73, 0.54, 0.36),
                shade: PetColor(0.57, 0.40, 0.26),
                belly: PetColor(0.97, 0.91, 0.82),
                accent: PetColor(0.38, 0.62, 0.95),
                sky: [PetColor(0.81, 0.90, 0.99), PetColor(0.60, 0.75, 0.96)]
            )
        case .bunny:
            PetColorScheme(
                coat: PetColor(0.95, 0.94, 0.97),
                shade: PetColor(0.82, 0.81, 0.88),
                belly: PetColor(1.00, 0.99, 1.00),
                accent: PetColor(0.98, 0.62, 0.72),
                sky: [PetColor(0.93, 0.97, 0.90), PetColor(0.76, 0.90, 0.81)]
            )
        case .dragon:
            PetColorScheme(
                coat: PetColor(0.40, 0.78, 0.62),
                shade: PetColor(0.25, 0.58, 0.46),
                belly: PetColor(0.94, 0.95, 0.70),
                accent: PetColor(0.99, 0.66, 0.30),
                sky: [PetColor(0.32, 0.38, 0.56), PetColor(0.16, 0.20, 0.36)]
            )
        case .monkey:
            PetColorScheme(
                coat: PetColor(0.62, 0.45, 0.32),
                shade: PetColor(0.45, 0.31, 0.21),
                belly: PetColor(0.96, 0.86, 0.72),
                accent: PetColor(0.94, 0.52, 0.40),
                sky: [PetColor(0.87, 0.95, 0.78), PetColor(0.53, 0.79, 0.56)]
            )
        }
    }

    /// The palette for a stock member of this species. A pet the owner has recoloured
    /// goes through `Pet.palette` instead.
    var palette: PetPalette { PetAppearance().palette(for: self) }

    /// Synthesiser settings. Nothing is sampled from disk — every noise this app makes
    /// is generated from these numbers at runtime.
    var voice: VoiceProfile {
        switch self {
        case .cat:
            VoiceProfile(
                pitch: 520, purrPitch: 52, purrRate: 26, brightness: 0.6,
                comfort: .purr, lonely: .meow, delighted: .trill,
                eating: .munch, playing: .chirp, grumpy: .growl
            )
        case .dog:
            VoiceProfile(
                pitch: 300, purrPitch: 78, purrRate: 4.4, brightness: 0.45,
                comfort: .snuffle, lonely: .bark, delighted: .yip,
                eating: .munch, playing: .bark, grumpy: .whine
            )
        case .bunny:
            VoiceProfile(
                pitch: 880, purrPitch: 120, purrRate: 34, brightness: 0.8,
                comfort: .purr, lonely: .squeak, delighted: .squeak,
                eating: .munch, playing: .thump, grumpy: .thump
            )
        case .dragon:
            VoiceProfile(
                pitch: 200, purrPitch: 38, purrRate: 13, brightness: 0.35,
                comfort: .purr, lonely: .roar, delighted: .trill,
                eating: .munch, playing: .roar, grumpy: .growl
            )
        case .monkey:
            VoiceProfile(
                pitch: 700, purrPitch: 96, purrRate: 18, brightness: 0.78,
                comfort: .snuffle, lonely: .chirp, delighted: .trill,
                eating: .munch, playing: .yip, grumpy: .growl
            )
        }
    }
}

enum EarStyle: Sendable {
    case pointed
    case floppy
    case tall
    case horned
    case round
}

struct PetPalette: Sendable {
    let body: Color
    let shade: Color
    let belly: Color
    let accent: Color
    /// Two-stop gradient used behind the pet.
    let sky: [Color]
}

/// Every noise the pet can make. Nothing here is a recording — the waveforms are
/// generated from scratch at launch, so the app ships without a single audio file.
enum PetSound: String, Sendable, CaseIterable {
    case purr
    case snuffle
    case meow
    case bark
    case yip
    case whine
    case chirp
    case trill
    case squeak
    case munch
    case growl
    case roar
    case thump

    /// Comfort sounds are built to loop seamlessly; the rest are one-shots.
    var isLoopable: Bool { self == .purr || self == .snuffle }
}

/// The handful of numbers that turn a species into a sound.
struct VoiceProfile: Sendable {
    /// Base frequency of the pet's "words", in hertz.
    let pitch: Double
    /// Carrier frequency of the comfort rumble.
    let purrPitch: Double
    /// Pulses per second in the comfort rumble.
    let purrRate: Double
    /// How much upper harmonic content the voice carries, 0...1.
    let brightness: Double

    let comfort: PetSound
    let lonely: PetSound
    let delighted: PetSound
    let eating: PetSound
    let playing: PetSound
    let grumpy: PetSound
}
