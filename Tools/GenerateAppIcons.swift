#!/usr/bin/env swift
//
//  GenerateAppIcons.swift
//
//  Draws the 1024×1024 app icon artwork for every species × coat colour the designer can
//  produce and writes it into Assets.xcassets as `AppIcon-<species>-<coat>`. The shapes,
//  colours and colour derivations mirror PetFaceView / PetKind / PetAppearance, so a
//  charcoal dragon on the Home Screen looks like the charcoal dragon in the app.
//
//  Each set holds one image per Home Screen appearance:
//
//  - `icon.png`        the default look: the pet over its own full-bleed backdrop.
//  - `icon-dark.png`   the pet alone on transparency, so the system's dark backdrop shows
//                      through. Coats too dark to read against it are lifted.
//  - `icon-tinted.png` the pet alone in greys. iOS builds both the tinted and the Liquid
//                      Glass clear appearances out of this layer: its alpha decides the
//                      shape of the glass and its greys decide how strongly each feature
//                      reads through it. A flattened icon gives the system nothing to cut
//                      the glass with, which is why the clear appearance needs this layer
//                      rather than the default one.
//
//  iOS can only pick from icons baked into the bundle, so a pet whose coat came from the
//  colour picker rather than a swatch gets the nearest of these at runtime — see
//  PetAppIcon.name(for:).
//
//  Run from the repo root:  swift Tools/GenerateAppIcons.swift
//

import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// MARK: - Colours

struct RGB {
    let r: Double, g: Double, b: Double
    init(_ r: Double, _ g: Double, _ b: Double) { self.r = r; self.g = g; self.b = b }
    var components: [CGFloat] { [CGFloat(r), CGFloat(g), CGFloat(b), 1] }
    var cgColor: CGColor { CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: 1) }
    func opacity(_ alpha: Double) -> CGColor {
        CGColor(red: CGFloat(r), green: CGFloat(g), blue: CGFloat(b), alpha: CGFloat(alpha))
    }

    // The three mixers below match PetColor, so a recoloured pet's shade and backdrop come
    // out of this script exactly as the app derives them.
    func mixed(with other: RGB, amount: Double) -> RGB {
        let t = min(max(amount, 0), 1)
        return RGB(r + (other.r - r) * t, g + (other.g - g) * t, b + (other.b - b) * t)
    }

    func lightened(by amount: Double) -> RGB { mixed(with: RGB(1, 1, 1), amount: amount) }

    func darkened(by amount: Double) -> RGB { mixed(with: RGB(0.06, 0.05, 0.09), amount: amount) }

    func matches(_ other: RGB) -> Bool { r == other.r && g == other.g && b == other.b }

    /// Relative luminance, used to judge whether a coat will read against the system's
    /// dark backdrop.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }

    /// The same hue lifted or pulled back until its luminance lands inside `range`.
    func luminance(within range: ClosedRange<Double>) -> RGB {
        let current = luminance
        if current < range.lowerBound {
            return lightened(by: (range.lowerBound - current) / max(1 - current, 0.001))
        }
        if current > range.upperBound {
            let floorLuminance = RGB(0.06, 0.05, 0.09).luminance
            return darkened(by: (current - range.upperBound) / max(current - floorLuminance, 0.001))
        }
        return self
    }
}

func grey(_ value: Double) -> RGB { RGB(value, value, value) }

/// The ready-made coat colours from `PetSwatches.coat`. The slug is the asset catalog name
/// suffix, and must stay in step with `PetSwatch.slug`.
struct CoatSwatch {
    let slug: String
    let color: RGB

    init(_ name: String, _ r: Double, _ g: Double, _ b: Double) {
        self.slug = name.lowercased()
        self.color = RGB(r, g, b)
    }
}

let coatSwatches: [CoatSwatch] = [
    CoatSwatch("Ginger", 0.97, 0.74, 0.44),
    CoatSwatch("Chestnut", 0.73, 0.54, 0.36),
    CoatSwatch("Cocoa", 0.50, 0.36, 0.27),
    CoatSwatch("Charcoal", 0.32, 0.33, 0.38),
    CoatSwatch("Snow", 0.95, 0.94, 0.97),
    CoatSwatch("Cream", 0.96, 0.89, 0.76),
    CoatSwatch("Rose", 0.96, 0.66, 0.70),
    CoatSwatch("Lilac", 0.72, 0.65, 0.93),
    CoatSwatch("Sky", 0.55, 0.74, 0.95),
    CoatSwatch("Mint", 0.40, 0.78, 0.62),
    CoatSwatch("Moss", 0.55, 0.70, 0.40),
    CoatSwatch("Gold", 0.96, 0.82, 0.33)
]

// MARK: - Appearances

/// The Home Screen appearances the asset catalog carries. iOS derives the clear light and
/// clear dark looks from the tinted layer, so there is nothing to draw for those.
enum Appearance: String, CaseIterable {
    case light, dark, mono

    var filename: String {
        switch self {
        case .light: "icon.png"
        case .dark: "icon-dark.png"
        case .mono: "icon-tinted.png"
        }
    }

    /// The asset catalog's annotation for this image. The default image carries none.
    var luminosity: String? {
        switch self {
        case .light: nil
        case .dark: "dark"
        case .mono: "tinted"
        }
    }
}

/// A species' own colours, before the designer or the appearance gets to them.
struct Stock {
    let body: RGB
    let shade: RGB
    let belly: RGB
    let accent: RGB
    let sky: (RGB, RGB)
    let nose: RGB
}

/// Every colour one drawing pass needs. The shape code is shared across appearances; only
/// the palette handed to it changes.
struct Palette {
    /// The backdrop gradient, or nil where the system supplies the background — the dark
    /// and tinted layers are foreground-only so the Liquid Glass material can sit behind.
    let sky: (RGB, RGB)?
    let body: RGB
    let shade: RGB
    let belly: RGB
    let accent: RGB
    let nose: RGB
    let eyeWhite: RGB
    let pupil: RGB
    /// nil where the variant leaves the blush out — at 22% it is a smudge, not a cheek.
    let cheek: RGB?
    let tongue: RGB
    /// True for the monochrome layer, which paints every translucent wash solid.
    let isMono: Bool

    /// `color` at `opacity`, except in the monochrome layer where washes go solid: partial
    /// alpha becomes partial glass, and a half-there whisker reads as a blur rather than a
    /// whisker once the system has refracted it.
    func wash(_ color: RGB, _ opacity: Double) -> CGColor {
        color.opacity(isMono ? 1 : opacity)
    }
}

enum Species: String, CaseIterable {
    case cat, dog, bunny, dragon, monkey

    /// The species' colours before anything the owner changed in the designer.
    var stock: Stock {
        switch self {
        case .cat:
            Stock(body: RGB(0.97, 0.74, 0.44), shade: RGB(0.87, 0.58, 0.30),
                  belly: RGB(0.99, 0.94, 0.86), accent: RGB(0.95, 0.55, 0.62),
                  sky: (RGB(0.99, 0.87, 0.74), RGB(0.97, 0.69, 0.63)),
                  nose: RGB(0.95, 0.55, 0.62))
        case .dog:
            Stock(body: RGB(0.73, 0.54, 0.36), shade: RGB(0.57, 0.40, 0.26),
                  belly: RGB(0.97, 0.91, 0.82), accent: RGB(0.38, 0.62, 0.95),
                  sky: (RGB(0.81, 0.90, 0.99), RGB(0.60, 0.75, 0.96)),
                  nose: RGB(0.22, 0.16, 0.13))
        case .bunny:
            Stock(body: RGB(0.95, 0.94, 0.97), shade: RGB(0.82, 0.81, 0.88),
                  belly: RGB(1.00, 0.99, 1.00), accent: RGB(0.98, 0.62, 0.72),
                  sky: (RGB(0.93, 0.97, 0.90), RGB(0.76, 0.90, 0.81)),
                  nose: RGB(0.98, 0.62, 0.72))
        case .dragon:
            Stock(body: RGB(0.40, 0.78, 0.62), shade: RGB(0.25, 0.58, 0.46),
                  belly: RGB(0.94, 0.95, 0.70), accent: RGB(0.99, 0.66, 0.30),
                  sky: (RGB(0.32, 0.38, 0.56), RGB(0.16, 0.20, 0.36)),
                  nose: RGB(0.16, 0.24, 0.21))
        case .monkey:
            Stock(body: RGB(0.62, 0.45, 0.32), shade: RGB(0.45, 0.31, 0.21),
                  belly: RGB(0.96, 0.86, 0.72), accent: RGB(0.94, 0.52, 0.40),
                  sky: (RGB(0.87, 0.95, 0.78), RGB(0.53, 0.79, 0.56)),
                  nose: RGB(0.30, 0.20, 0.16))
        }
    }

    /// This species wearing `coat`, dressed for `appearance`. The coat is derived exactly
    /// as `PetAppearance.colors(for:)` does: the shade is mixed from the coat, and the
    /// backdrop from the coat and accent.
    func palette(coat: RGB, appearance: Appearance) -> Palette {
        let stock = stock
        // An untouched coat keeps the species' hand-picked shade and backdrop.
        let recoloured = !coat.matches(stock.body)
        let body = recoloured ? coat : stock.body
        let shade = recoloured ? coat.darkened(by: 0.22) : stock.shade
        let sky = recoloured
            ? (coat.lightened(by: 0.74), stock.accent.lightened(by: 0.42))
            : stock.sky

        switch appearance {
        case .light:
            return Palette(
                sky: sky, body: body, shade: shade, belly: stock.belly, accent: stock.accent,
                nose: stock.nose, eyeWhite: RGB(1, 1, 1), pupil: RGB(0.08, 0.08, 0.10),
                cheek: RGB(0.98, 0.45, 0.48), tongue: RGB(0.95, 0.42, 0.52), isMono: false
            )

        case .dark:
            // The system's dark backdrop is near-black, so a charcoal coat is lifted until
            // it separates from it and a snow one is pulled back off the glare. The belly
            // comes down with it: a near-white muzzle is the brightest thing on the icon
            // otherwise, and it takes over.
            let lit = body.luminance(within: 0.42...0.86)
            return Palette(
                sky: nil, body: lit, shade: lit.darkened(by: 0.24),
                belly: stock.belly.darkened(by: 0.26), accent: stock.accent, nose: stock.nose,
                eyeWhite: RGB(0.92, 0.92, 0.94), pupil: RGB(0.06, 0.06, 0.08),
                cheek: RGB(0.98, 0.45, 0.48), tongue: RGB(0.82, 0.34, 0.44), isMono: false
            )

        case .mono:
            // Fixed greys rather than a desaturated coat: the tinted and clear appearances
            // throw the colour away, so a snow bunny and a charcoal one have to arrive at
            // the same legible silhouette. The greys are chosen by feature — muzzle and
            // eyes forward, nose and pupils back — so the face still has depth once the
            // system renders it as glass.
            return Palette(
                sky: nil, body: grey(0.60), shade: grey(0.44), belly: grey(0.92),
                accent: grey(0.80), nose: grey(0.20), eyeWhite: grey(1.00), pupil: grey(0.10),
                cheek: nil, tongue: grey(0.36), isMono: true
            )
        }
    }

    /// Vertical extent of the drawing in face-space units, used to centre each species
    /// on the canvas. Bunny ears reach a lot further up than a cat's do.
    var verticalBounds: (top: Double, bottom: Double) {
        switch self {
        case .cat: (-142, 106)
        case .dog: (-108, 110)
        case .bunny: (-200, 106)
        case .dragon: (-145, 106)
        case .monkey: (-108, 110)
        }
    }
}

// MARK: - Canvas

let side = 1024
/// Face-space units per pixel. PetFaceView draws a 224-wide head; 2.5 puts it at 560px.
let faceScale: Double = 2.5

func makeContext() -> CGContext {
    let context = CGContext(
        data: nil,
        width: side,
        height: side,
        bitsPerComponent: 8,
        bytesPerRow: 0,
        space: CGColorSpace(name: CGColorSpace.sRGB)!,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    // Flip to a top-left origin so the maths matches SwiftUI's coordinate space.
    context.translateBy(x: 0, y: CGFloat(side))
    context.scaleBy(x: 1, y: -1)
    return context
}

func fillGradient(_ context: CGContext, from top: RGB, to bottom: RGB, in rect: CGRect) {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let gradient = CGGradient(
        colorsSpace: space,
        colors: [top.cgColor, bottom.cgColor] as CFArray,
        locations: [0, 1]
    )!
    context.saveGState()
    context.clip(to: rect)
    context.drawLinearGradient(
        gradient,
        start: CGPoint(x: rect.midX, y: rect.minY),
        end: CGPoint(x: rect.midX, y: rect.maxY),
        options: []
    )
    context.restoreGState()
}

func fillEllipseGradient(_ context: CGContext, rect: CGRect, from top: RGB, to bottom: RGB) {
    context.saveGState()
    context.addEllipse(in: rect)
    context.clip()
    fillGradient(context, from: top, to: bottom, in: rect)
    context.restoreGState()
}

/// A triangle pointing up, matching the app's `Triangle` shape.
func trianglePath(in rect: CGRect, pointingDown: Bool = false) -> CGPath {
    let path = CGMutablePath()
    if pointingDown {
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
    } else {
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
    }
    path.closeSubpath()
    return path
}

func capsulePath(in rect: CGRect) -> CGPath {
    CGPath(roundedRect: rect, cornerWidth: rect.width / 2, cornerHeight: rect.height / 2, transform: nil)
}

// MARK: - Drawing in face space

/// Wraps a `CGContext` so shapes can be placed using PetFaceView's coordinates:
/// the origin is the centre of the head, y grows downwards.
struct FaceCanvas {
    let context: CGContext
    let origin: CGPoint
    let scale: Double

    func point(_ x: Double, _ y: Double) -> CGPoint {
        CGPoint(x: origin.x + CGFloat(x * scale), y: origin.y + CGFloat(y * scale))
    }

    /// A rect centred on (x, y) in face space.
    func rect(x: Double = 0, y: Double = 0, width: Double, height: Double) -> CGRect {
        CGRect(
            x: origin.x + CGFloat((x - width / 2) * scale),
            y: origin.y + CGFloat((y - height / 2) * scale),
            width: CGFloat(width * scale),
            height: CGFloat(height * scale)
        )
    }

    func length(_ value: Double) -> CGFloat { CGFloat(value * scale) }

    /// Runs `draw` with the canvas rotated about a face-space anchor point.
    func rotated(degrees: Double, about anchor: CGPoint, _ draw: () -> Void) {
        context.saveGState()
        context.translateBy(x: anchor.x, y: anchor.y)
        context.rotate(by: CGFloat(degrees * .pi / 180))
        context.translateBy(x: -anchor.x, y: -anchor.y)
        draw()
        context.restoreGState()
    }
}

func drawEars(_ canvas: FaceCanvas, species: Species, palette: Palette) {
    let context = canvas.context

    switch species {
    case .cat:
        for side in [-1.0, 1.0] {
            let centre = canvas.point(side * 72, -96)
            canvas.rotated(degrees: side * 14, about: centre) {
                context.setFillColor(palette.body.cgColor)
                context.addPath(trianglePath(in: canvas.rect(x: side * 72, y: -96, width: 68, height: 64)))
                context.fillPath()
                context.setFillColor(palette.wash(palette.accent, 0.65))
                context.addPath(trianglePath(in: canvas.rect(x: side * 72, y: -84, width: 34, height: 32)))
                context.fillPath()
            }
        }

    case .dog:
        // Pushed a little further out than in PetFaceView: at icon size an ear tucked
        // behind the head reads as a bump rather than an ear.
        for side in [-1.0, 1.0] {
            let centre = canvas.point(side * 108, 2)
            canvas.rotated(degrees: side * 16, about: centre) {
                fillEllipseGradient(
                    context,
                    rect: canvas.rect(x: side * 108, y: 2, width: 56, height: 138),
                    from: palette.shade,
                    to: palette.body
                )
            }
        }

    case .bunny:
        for side in [-1.0, 1.0] {
            let centre = canvas.point(side * 48, -136)
            canvas.rotated(degrees: side * 9, about: centre) {
                context.setFillColor(palette.body.cgColor)
                context.addPath(capsulePath(in: canvas.rect(x: side * 48, y: -136, width: 42, height: 122)))
                context.fillPath()
                context.setFillColor(palette.wash(palette.accent, 0.5))
                context.addPath(capsulePath(in: canvas.rect(x: side * 48, y: -136, width: 20, height: 92)))
                context.fillPath()
            }
        }

    case .dragon:
        for side in [-1.0, 1.0] {
            let centre = canvas.point(side * 62, -106)
            canvas.rotated(degrees: side * 24, about: centre) {
                context.setFillColor(palette.belly.cgColor)
                context.addPath(trianglePath(in: canvas.rect(x: side * 62, y: -106, width: 32, height: 62)))
                context.fillPath()
            }
        }
        // A little crest of spines, tallest in the middle.
        for index in 0..<3 {
            let height = 18 + Double(1 - abs(index - 1)) * 8
            let x = Double(index - 1) * 20
            context.setFillColor(palette.accent.cgColor)
            context.addPath(trianglePath(in: canvas.rect(x: x, y: -104, width: 16, height: height)))
            context.fillPath()
        }

    case .monkey:
        // Big discs either side of the head.
        for side in [-1.0, 1.0] {
            fillEllipseGradient(
                context,
                rect: canvas.rect(x: side * 102, y: -26, width: 70, height: 70),
                from: palette.body,
                to: palette.shade
            )
            context.setFillColor(palette.wash(palette.accent, 0.55))
            context.fillEllipse(in: canvas.rect(x: side * 102, y: -26, width: 36, height: 36))
        }
    }
}

func drawHead(_ canvas: FaceCanvas, species: Species, palette: Palette) {
    let context = canvas.context

    fillEllipseGradient(
        context,
        rect: canvas.rect(width: 224, height: 206),
        from: palette.body,
        to: palette.shade
    )

    context.setFillColor(palette.wash(palette.belly, 0.95))
    context.fillEllipse(in: canvas.rect(y: 48, width: 132, height: 86))

    if species == .dragon {
        // A row of belly scales.
        for index in 0..<4 {
            let x = (Double(index) - 1.5) * 22
            context.setFillColor(palette.wash(palette.shade, 0.35))
            context.addPath(capsulePath(in: canvas.rect(x: x, y: 84, width: 16, height: 8)))
            context.fillPath()
        }
    }
}

func drawFace(_ canvas: FaceCanvas, species: Species, palette: Palette) {
    let context = canvas.context

    // Cheeks, where the variant keeps them.
    if let cheek = palette.cheek {
        for side in [-1.0, 1.0] {
            context.setFillColor(cheek.opacity(0.22))
            context.fillEllipse(in: canvas.rect(x: side * 84, y: 30, width: 46, height: 34))
        }
    }

    // Eyes, open and bright — an icon should look pleased to see you.
    for side in [-1.0, 1.0] {
        context.setFillColor(palette.eyeWhite.cgColor)
        context.fillEllipse(in: canvas.rect(x: side * 48, y: -16, width: 46, height: 46))
        context.setFillColor(palette.pupil.cgColor)
        context.fillEllipse(in: canvas.rect(x: side * 48, y: -14, width: 22, height: 22))
        context.setFillColor(palette.eyeWhite.cgColor)
        context.fillEllipse(in: canvas.rect(x: side * 48 + 5, y: -22, width: 8, height: 8))
    }

    // Nose: a downward triangle with its corners taken off.
    context.saveGState()
    let noseRect = canvas.rect(y: 24, width: 26, height: 16)
    context.addPath(trianglePath(in: noseRect, pointingDown: true))
    context.setFillColor(palette.nose.cgColor)
    context.fillPath()
    context.restoreGState()

    // Smile.
    let mouth = CGMutablePath()
    mouth.move(to: canvas.point(-28, 48))
    mouth.addQuadCurve(to: canvas.point(28, 48), control: canvas.point(0, 70))
    context.addPath(mouth)
    context.setStrokeColor(palette.wash(palette.nose, 0.75))
    context.setLineWidth(canvas.length(5))
    context.setLineCap(.round)
    context.strokePath()

    if species == .cat {
        // Thicker in the mono layer: a 3-unit hair survives the default icon but the glass
        // refracts it away to nothing.
        let thickness = palette.isMono ? 5.0 : 3.0
        for side in [-1.0, 1.0] {
            for index in 0..<3 {
                let y = 32 + Double(index - 1) * 9
                let centre = canvas.point(side * 90, y)
                canvas.rotated(degrees: side * Double(index - 1) * 13, about: centre) {
                    context.setFillColor(palette.wash(palette.shade, 0.55))
                    context.addPath(capsulePath(in: canvas.rect(x: side * 90, y: y, width: 46, height: thickness)))
                    context.fillPath()
                }
            }
        }
    }

    if species == .dog {
        // Tongue out, because of course it is.
        context.setFillColor(palette.tongue.cgColor)
        context.addPath(capsulePath(in: canvas.rect(y: 66, width: 20, height: 28)))
        context.fillPath()
    }
}

func renderIcon(species: Species, coat: RGB, appearance: Appearance) -> CGImage {
    let context = makeContext()
    let palette = species.palette(coat: coat, appearance: appearance)
    if let sky = palette.sky {
        fillGradient(context, from: sky.0, to: sky.1, in: CGRect(x: 0, y: 0, width: side, height: side))
    }

    // Centre the species' own vertical extent on the canvas.
    let bounds = species.verticalBounds
    let midpoint = (bounds.top + bounds.bottom) / 2
    let canvas = FaceCanvas(
        context: context,
        origin: CGPoint(x: CGFloat(side) / 2, y: CGFloat(side) / 2 - CGFloat(midpoint * faceScale)),
        scale: faceScale
    )

    drawEars(canvas, species: species, palette: palette)
    drawHead(canvas, species: species, palette: palette)
    drawFace(canvas, species: species, palette: palette)

    return context.makeImage()!
}

/// The icon shown before anyone has adopted a pet: a paw print, no species implied.
func renderPrimary(appearance: Appearance) -> CGImage {
    let context = makeContext()
    if appearance == .light {
        fillGradient(
            context,
            from: RGB(0.99, 0.87, 0.74),
            to: RGB(0.97, 0.62, 0.58),
            in: CGRect(x: 0, y: 0, width: side, height: side)
        )
    }

    let paw = switch appearance {
    case .light: RGB(0.99, 0.96, 0.92)
    // Off the glare on the system's dark backdrop, and a near-white pad in the mono layer:
    // the paw is the whole icon, so it wants the full strength of the glass.
    case .dark: RGB(0.99, 0.96, 0.92).darkened(by: 0.12)
    case .mono: grey(0.94)
    }
    context.setFillColor(paw.cgColor)

    // Main pad.
    context.fillEllipse(in: CGRect(x: 512 - 190, y: 460, width: 380, height: 320))

    // Four toes, fanned above the pad.
    let toes: [(x: Double, y: Double, w: Double, h: Double, angle: Double)] = [
        (-232, 380, 120, 165, -26),
        (-84, 345, 132, 182, -9),
        (84, 345, 132, 182, 9),
        (232, 380, 120, 165, 26)
    ]
    for toe in toes {
        let rect = CGRect(
            x: 512 + toe.x - toe.w / 2,
            y: toe.y - toe.h / 2,
            width: toe.w,
            height: toe.h
        )
        let centre = CGPoint(x: rect.midX, y: rect.midY)
        context.saveGState()
        context.translateBy(x: centre.x, y: centre.y)
        context.rotate(by: CGFloat(toe.angle * .pi / 180))
        context.translateBy(x: -centre.x, y: -centre.y)
        context.fillEllipse(in: rect)
        context.restoreGState()
    }

    return context.makeImage()!
}

// MARK: - Asset catalog output

let catalog = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    .appendingPathComponent("Virtual Pet/Assets.xcassets")

func writePNG(_ image: CGImage, to url: URL) throws {
    guard let destination = CGImageDestinationCreateWithURL(
        url as CFURL, UTType.png.identifier as CFString, 1, nil
    ) else {
        throw CocoaError(.fileWriteUnknown)
    }
    CGImageDestinationAddImage(destination, image, nil)
    guard CGImageDestinationFinalize(destination) else { throw CocoaError(.fileWriteUnknown) }
}

/// The `Contents.json` that hands iOS one image per appearance. Shared by every set, since
/// they all carry the same three filenames.
func contentsJSON() throws -> Data {
    let images: [[String: Any]] = Appearance.allCases.map { appearance in
        var image: [String: Any] = [
            "filename": appearance.filename,
            "idiom": "universal",
            "platform": "ios",
            "size": "1024x1024"
        ]
        if let luminosity = appearance.luminosity {
            image["appearances"] = [["appearance": "luminosity", "value": luminosity]]
        }
        return image
    }
    let root: [String: Any] = ["images": images, "info": ["author": "xcode", "version": 1]]
    var data = try JSONSerialization.data(withJSONObject: root, options: [.prettyPrinted, .sortedKeys])
    data.append(0x0A)
    return data
}

let contents = try contentsJSON()

func write(iconSetNamed name: String, render: (Appearance) -> CGImage) throws {
    let setURL = catalog.appendingPathComponent("\(name).appiconset")
    try FileManager.default.createDirectory(at: setURL, withIntermediateDirectories: true)

    for appearance in Appearance.allCases {
        try writePNG(render(appearance), to: setURL.appendingPathComponent(appearance.filename))
    }
    try contents.write(to: setURL.appendingPathComponent("Contents.json"))
}

var written: Set<String> = []

try write(iconSetNamed: "AppIcon") { renderPrimary(appearance: $0) }
written.insert("AppIcon")

for species in Species.allCases {
    // A pet that has never been recoloured, whose stock coat may not be one of the
    // swatches at all — the monkey's isn't.
    let stock = "AppIcon-\(species.rawValue)-stock"
    try write(iconSetNamed: stock) { renderIcon(species: species, coat: species.stock.body, appearance: $0) }
    written.insert(stock)

    for swatch in coatSwatches {
        let name = "AppIcon-\(species.rawValue)-\(swatch.slug)"
        try write(iconSetNamed: name) { renderIcon(species: species, coat: swatch.color, appearance: $0) }
        written.insert(name)
    }
}
print("wrote \(written.count) icon sets")

// Clear out sets from an earlier run — a renamed swatch or a dropped species would
// otherwise leave dead 1MB icons in the bundle.
let existing = try FileManager.default.contentsOfDirectory(atPath: catalog.path)
for entry in existing where entry.hasSuffix(".appiconset") {
    let name = String(entry.dropLast(".appiconset".count))
    guard !written.contains(name) else { continue }
    try FileManager.default.removeItem(at: catalog.appendingPathComponent(entry))
    print("removed stale \(entry)")
}
