import SwiftUI

/// A colour that can be saved alongside the pet. SwiftUI's `Color` isn't `Codable`, so
/// everything the owner picks in the designer is stored as plain sRGB components.
///
/// Nonisolated because three numbers are three numbers wherever they are read from.
nonisolated struct PetColor: Codable, Sendable, Equatable, Hashable {
    var red: Double
    var green: Double
    var blue: Double

    init(_ red: Double, _ green: Double, _ blue: Double) {
        self.red = min(max(red, 0), 1)
        self.green = min(max(green, 0), 1)
        self.blue = min(max(blue, 0), 1)
    }

    /// Pulls components out of a SwiftUI colour. This needs an environment because a
    /// `Color` can be a dynamic thing — an asset, or `.primary` — until it is resolved.
    init(_ color: Color, in environment: EnvironmentValues) {
        let resolved = color.resolve(in: environment)
        self.init(Double(resolved.red), Double(resolved.green), Double(resolved.blue))
    }

    var color: Color { Color(red: red, green: green, blue: blue) }

    func mixed(with other: PetColor, amount: Double) -> PetColor {
        let t = min(max(amount, 0), 1)
        return PetColor(
            red + (other.red - red) * t,
            green + (other.green - green) * t,
            blue + (other.blue - blue) * t
        )
    }

    func lightened(by amount: Double) -> PetColor {
        mixed(with: PetColor(1, 1, 1), amount: amount)
    }

    /// Shades are mixed towards a very dark blue rather than pure black, which keeps a
    /// recoloured pet's shading from going flat and muddy.
    func darkened(by amount: Double) -> PetColor {
        mixed(with: PetColor(0.06, 0.05, 0.09), amount: amount)
    }
}

/// Every colour it takes to draw a pet and the world behind it.
struct PetColorScheme: Sendable, Equatable {
    var coat: PetColor
    var shade: PetColor
    var belly: PetColor
    var accent: PetColor
    /// Two-stop gradient used behind the pet.
    var sky: [PetColor]
}

/// How big the pet is drawn. Purely cosmetic — a huge pet is no hungrier than a tiny one.
enum PetSize: String, CaseIterable, Codable, Identifiable, Sendable {
    case tiny
    case small
    case regular
    case big
    case huge

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .tiny: "Tiny"
        case .small: "Small"
        case .regular: "Regular"
        case .big: "Big"
        case .huge: "Huge"
        }
    }

    var detail: String {
        switch self {
        case .tiny: "Pocket-sized. Easy to lose in a pile of washing."
        case .small: "Neat, tidy and mostly out of the way."
        case .regular: "Just right."
        case .big: "Takes up rather a lot of the sofa."
        case .huge: "Barely fits on the screen. Regrets nothing."
        }
    }

    var scale: Double {
        switch self {
        case .tiny: 0.70
        case .small: 0.85
        case .regular: 1.00
        case .big: 1.16
        case .huge: 1.32
        }
    }
}

/// Everything the owner has chosen about how their pet looks. Each colour is optional
/// and `nil` means "whatever this species normally is", so a pet that has never been
/// recoloured keeps following its species' hand-picked palette — including after the
/// owner changes species.
struct PetAppearance: Codable, Sendable, Equatable {
    var coat: PetColor?
    var belly: PetColor?
    var accent: PetColor?
    var size: PetSize

    init(coat: PetColor? = nil, belly: PetColor? = nil, accent: PetColor? = nil, size: PetSize = .regular) {
        self.coat = coat
        self.belly = belly
        self.accent = accent
        self.size = size
    }

    // Decoded defensively, so a pet saved before the designer existed still loads.
    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        coat = try container.decodeIfPresent(PetColor.self, forKey: .coat)
        belly = try container.decodeIfPresent(PetColor.self, forKey: .belly)
        accent = try container.decodeIfPresent(PetColor.self, forKey: .accent)
        size = try container.decodeIfPresent(PetSize.self, forKey: .size) ?? .regular
    }

    var isCustomised: Bool {
        coat != nil || belly != nil || accent != nil || size != .regular
    }

    /// Resolves the owner's choices against a species' stock colours.
    func colors(for kind: PetKind) -> PetColorScheme {
        let base = kind.colors
        let coat = self.coat ?? base.coat
        let accent = self.accent ?? base.accent
        return PetColorScheme(
            coat: coat,
            // The stock shade is hand-picked per species, but a recoloured coat needs a
            // shade mixed to match it rather than the one the species came with.
            shade: self.coat.map { $0.darkened(by: 0.22) } ?? base.shade,
            belly: belly ?? base.belly,
            accent: accent,
            // Same story for the backdrop: left alone until the pet itself is recoloured,
            // then mixed from the pet's own colours so the two never clash.
            sky: (self.coat == nil && self.accent == nil)
                ? base.sky
                : [coat.lightened(by: 0.74), accent.lightened(by: 0.42)]
        )
    }

    func palette(for kind: PetKind) -> PetPalette {
        let scheme = colors(for: kind)
        return PetPalette(
            body: scheme.coat.color,
            shade: scheme.shade.color,
            belly: scheme.belly.color,
            accent: scheme.accent.color,
            sky: scheme.sky.map(\.color)
        )
    }
}

/// A named colour offered in the designer. The names are there for VoiceOver as much as
/// for the labels — "swatch 7" is no use to anybody.
///
/// Nonisolated because a swatch is a constant, not UI state: the app icon picker looks
/// colours up off the main actor.
nonisolated struct PetSwatch: Identifiable, Sendable {
    let name: String
    let color: PetColor

    var id: String { name }

    /// Used to build app icon asset names, so renaming a swatch means regenerating the
    /// icons — see `Tools/GenerateAppIcons.swift` and ``PetAppIcon``.
    var slug: String { name.lowercased() }

    init(_ name: String, _ red: Double, _ green: Double, _ blue: Double) {
        self.name = name
        self.color = PetColor(red, green, blue)
    }
}

/// The ready-made colours in the designer. Anything outside these is still reachable
/// through the colour picker next to each row.
nonisolated enum PetSwatches {
    static let coat: [PetSwatch] = [
        PetSwatch("Ginger", 0.97, 0.74, 0.44),
        PetSwatch("Chestnut", 0.73, 0.54, 0.36),
        PetSwatch("Cocoa", 0.50, 0.36, 0.27),
        PetSwatch("Charcoal", 0.32, 0.33, 0.38),
        PetSwatch("Snow", 0.95, 0.94, 0.97),
        PetSwatch("Cream", 0.96, 0.89, 0.76),
        PetSwatch("Rose", 0.96, 0.66, 0.70),
        PetSwatch("Lilac", 0.72, 0.65, 0.93),
        PetSwatch("Sky", 0.55, 0.74, 0.95),
        PetSwatch("Mint", 0.40, 0.78, 0.62),
        PetSwatch("Moss", 0.55, 0.70, 0.40),
        PetSwatch("Gold", 0.96, 0.82, 0.33)
    ]

    static let belly: [PetSwatch] = [
        PetSwatch("Cream", 0.99, 0.94, 0.86),
        PetSwatch("Snow", 1.00, 0.99, 1.00),
        PetSwatch("Oat", 0.97, 0.91, 0.82),
        PetSwatch("Lemon", 0.94, 0.95, 0.70),
        PetSwatch("Ice", 0.92, 0.96, 0.99),
        PetSwatch("Blush", 0.97, 0.90, 0.93),
        PetSwatch("Stone", 0.90, 0.88, 0.84),
        PetSwatch("Taupe", 0.84, 0.79, 0.72)
    ]

    static let accent: [PetSwatch] = [
        PetSwatch("Pink", 0.95, 0.55, 0.62),
        PetSwatch("Blossom", 0.98, 0.62, 0.72),
        PetSwatch("Red", 0.95, 0.36, 0.36),
        PetSwatch("Amber", 0.99, 0.66, 0.30),
        PetSwatch("Yellow", 0.96, 0.83, 0.28),
        PetSwatch("Green", 0.55, 0.82, 0.45),
        PetSwatch("Teal", 0.30, 0.80, 0.78),
        PetSwatch("Blue", 0.38, 0.62, 0.95),
        PetSwatch("Violet", 0.72, 0.52, 0.95),
        PetSwatch("Slate", 0.45, 0.47, 0.55)
    ]
}
