import SwiftUI

/// The species someone can adopt. Each kind carries its own silhouette, palette and voice,
/// so swapping species changes how the phone looks *and* how it sounds.
enum PetKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case cat
    case dog
    case bunny
    case dragon

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .cat: "Cat"
        case .dog: "Dog"
        case .bunny: "Bunny"
        case .dragon: "Dragon"
        }
    }

    var tagline: String {
        switch self {
        case .cat: "Purrs in your palm. Judges you from the table."
        case .dog: "Will absolutely tell the neighbours you left."
        case .bunny: "Small, twitchy, thumps when ignored."
        case .dragon: "Hoards your battery. Rumbles like a furnace."
        }
    }

    var symbolName: String {
        switch self {
        case .cat: "cat.fill"
        case .dog: "dog.fill"
        case .bunny: "hare.fill"
        case .dragon: "lizard.fill"
        }
    }

    var suggestedNames: [String] {
        switch self {
        case .cat: ["Mochi", "Biscuit", "Noodle", "Pixel"]
        case .dog: ["Rufus", "Waffle", "Bolt", "Pepper"]
        case .bunny: ["Clover", "Bean", "Nibbles", "Sprout"]
        case .dragon: ["Ember", "Cinder", "Toast", "Basil"]
        }
    }

    var favouriteFood: String {
        switch self {
        case .cat: "a tin of tuna"
        case .dog: "a strip of jerky"
        case .bunny: "a fistful of greens"
        case .dragon: "one (1) charcoal briquette"
        }
    }

    /// What this species will chase around the screen during a play session.
    var toySymbol: String {
        switch self {
        case .cat: "circle.fill"
        case .dog: "tennisball.fill"
        case .bunny: "leaf.fill"
        case .dragon: "flame.fill"
        }
    }

    var toyName: String {
        switch self {
        case .cat: "laser dot"
        case .dog: "tennis ball"
        case .bunny: "leaf"
        case .dragon: "spark"
        }
    }

    var toyColor: Color {
        switch self {
        case .cat: Color(red: 0.98, green: 0.18, blue: 0.22)
        case .dog: Color(red: 0.80, green: 0.90, blue: 0.25)
        case .bunny: Color(red: 0.35, green: 0.76, blue: 0.42)
        case .dragon: Color(red: 1.00, green: 0.58, blue: 0.15)
        }
    }

    var earStyle: EarStyle {
        switch self {
        case .cat: .pointed
        case .dog: .floppy
        case .bunny: .tall
        case .dragon: .horned
        }
    }

    /// True for species that can actually purr. Dogs get a contented groan instead.
    var canPurr: Bool { self != .dog }

    /// Noses are pink on the soft species and near-black on the others; using the accent
    /// colour everywhere left the dog with a bright blue nose.
    var noseColor: Color {
        switch self {
        case .cat, .bunny: palette.accent
        case .dog: Color(red: 0.22, green: 0.16, blue: 0.13)
        case .dragon: Color(red: 0.16, green: 0.24, blue: 0.21)
        }
    }

    var palette: PetPalette {
        switch self {
        case .cat:
            PetPalette(
                body: Color(red: 0.97, green: 0.74, blue: 0.44),
                shade: Color(red: 0.87, green: 0.58, blue: 0.30),
                belly: Color(red: 0.99, green: 0.94, blue: 0.86),
                accent: Color(red: 0.95, green: 0.55, blue: 0.62),
                sky: [Color(red: 0.99, green: 0.87, blue: 0.74), Color(red: 0.97, green: 0.69, blue: 0.63)]
            )
        case .dog:
            PetPalette(
                body: Color(red: 0.73, green: 0.54, blue: 0.36),
                shade: Color(red: 0.57, green: 0.40, blue: 0.26),
                belly: Color(red: 0.97, green: 0.91, blue: 0.82),
                accent: Color(red: 0.38, green: 0.62, blue: 0.95),
                sky: [Color(red: 0.81, green: 0.90, blue: 0.99), Color(red: 0.60, green: 0.75, blue: 0.96)]
            )
        case .bunny:
            PetPalette(
                body: Color(red: 0.95, green: 0.94, blue: 0.97),
                shade: Color(red: 0.82, green: 0.81, blue: 0.88),
                belly: Color(red: 1.00, green: 0.99, blue: 1.00),
                accent: Color(red: 0.98, green: 0.62, blue: 0.72),
                sky: [Color(red: 0.93, green: 0.97, blue: 0.90), Color(red: 0.76, green: 0.90, blue: 0.81)]
            )
        case .dragon:
            PetPalette(
                body: Color(red: 0.40, green: 0.78, blue: 0.62),
                shade: Color(red: 0.25, green: 0.58, blue: 0.46),
                belly: Color(red: 0.94, green: 0.95, blue: 0.70),
                accent: Color(red: 0.99, green: 0.66, blue: 0.30),
                sky: [Color(red: 0.32, green: 0.38, blue: 0.56), Color(red: 0.16, green: 0.20, blue: 0.36)]
            )
        }
    }

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
        }
    }
}

enum EarStyle: Sendable {
    case pointed
    case floppy
    case tall
    case horned
}

struct PetPalette: Sendable {
    let body: Color
    let shade: Color
    let belly: Color
    let accent: Color
    /// Two-stop gradient used behind the pet.
    let sky: [Color]
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
