import SwiftUI

/// The creature itself, drawn entirely from SwiftUI shapes so it scales cleanly and
/// needs no artwork. A `TimelineView` drives the breathing, blinking and tail so the pet
/// is never completely still.
struct PetFaceView: View {
    let pet: Pet
    var isBeingPetted = false
    var isHeld = false
    var excitement: Double = 0
    /// Where the eyes should look, in -1...1 on each axis.
    var gaze: CGSize = .zero
    /// Overrides the mood for as long as the pet is complaining about something.
    var isUpset = false
    /// Overrides the mood the other way: eyes wide, grin at maximum, everything moving
    /// faster. Used by the reunion show, where nothing is played down.
    var isThrilled = false

    private var palette: PetPalette { pet.palette }
    private var isSleepy: Bool {
        pet.needs.rest < 0.2 && !isBeingPetted && !isUpset && !isThrilled
    }

    /// Blush and tongue stay warm pink whatever the species' accent colour is.
    private static let blush = Color(red: 0.98, green: 0.45, blue: 0.48)
    private static let tongue = Color(red: 0.95, green: 0.42, blue: 0.52)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            let liveliness = isThrilled ? 1.0 : 0.35 + 0.65 * pet.moodScore
            let breath = sin(time * (1.4 + liveliness)) * 0.5 + 0.5
            let wiggle = isBeingPetted || isThrilled
                ? sin(time * (isThrilled ? 16 : 9)) * (1.5 + 3 * excitement)
                : 0
            let squish = 1 + 0.022 * breath
                + (isBeingPetted || isThrilled ? 0.03 * excitement : 0)

            ZStack {
                tail(time: time, liveliness: liveliness)
                ears(time: time, liveliness: liveliness)
                head(breath: breath)
                face(time: time, liveliness: liveliness)
            }
            .frame(width: 280, height: 300)
            .scaleEffect(x: squish, y: 2 - squish, anchor: .bottom)
            .rotationEffect(.degrees(wiggle))
            // The chosen size scales from the centre and leaves the layout alone, so a
            // huge pet grows into the space around it rather than shoving the screen about.
            .scaleEffect(pet.appearance.size.scale)
            .offset(y: isHeld ? -4 : 0)
            .animation(.easeInOut(duration: 0.4), value: isHeld)
            .animation(.spring(duration: 0.45), value: pet.appearance.size)
        }
    }

    // MARK: Head and body

    private func head(breath: Double) -> some View {
        ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [palette.body, palette.shade],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: 224, height: 206)
                .shadow(color: palette.shade.opacity(0.45), radius: 18, y: 10)

            // Muzzle / chest patch.
            Ellipse()
                .fill(palette.belly)
                .frame(width: 132, height: 86)
                .offset(y: 48)
                .opacity(0.95)

            if pet.kind == .dragon {
                // A row of belly scales for the dragon.
                HStack(spacing: 6) {
                    ForEach(0..<4, id: \.self) { _ in
                        Capsule()
                            .fill(palette.shade.opacity(0.35))
                            .frame(width: 16, height: 8)
                    }
                }
                .offset(y: 84)
            }
        }
    }

    // MARK: Ears

    @ViewBuilder
    private func ears(time: Double, liveliness: Double) -> some View {
        let twitch = sin(time * 3.1) * 3 * liveliness
        // Ears go down when sleepy, and further down when something is wrong.
        let droop = isUpset ? 22.0 : (isSleepy ? 14.0 : 0.0)

        switch pet.kind.earStyle {
        case .pointed:
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Triangle()
                        .fill(palette.body)
                        .frame(width: 68, height: 64)
                    Triangle()
                        .fill(palette.accent.opacity(0.65))
                        .frame(width: 34, height: 32)
                        .offset(y: 12)
                }
                .rotationEffect(.degrees(side * (14 + droop) + twitch * side))
                .offset(x: side * 72, y: -96)
            }

        case .floppy:
            ForEach([-1.0, 1.0], id: \.self) { side in
                Ellipse()
                    .fill(
                        LinearGradient(colors: [palette.shade, palette.body],
                                       startPoint: .top, endPoint: .bottom)
                    )
                    .frame(width: 52, height: 132)
                    .rotationEffect(.degrees(side * (16 + droop) + twitch * side))
                    .offset(x: side * 98, y: -4)
            }

        case .tall:
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Capsule()
                        .fill(palette.body)
                        .frame(width: 42, height: 122)
                    Capsule()
                        .fill(palette.accent.opacity(0.5))
                        .frame(width: 20, height: 92)
                }
                .rotationEffect(.degrees(side * (9 + droop * 2) + twitch * side * 1.6))
                .offset(x: side * 48, y: -136)
            }

        case .horned:
            ForEach([-1.0, 1.0], id: \.self) { side in
                Triangle()
                    .fill(palette.belly)
                    .frame(width: 32, height: 62)
                    .rotationEffect(.degrees(side * 24))
                    .offset(x: side * 62, y: -106)
            }
            // A little crest of spines.
            HStack(spacing: 4) {
                ForEach(0..<3, id: \.self) { index in
                    Triangle()
                        .fill(palette.accent)
                        .frame(width: 16, height: 18 + Double(1 - abs(index - 1)) * 8)
                }
            }
            .offset(y: -104)

        case .round:
            // Big discs either side of the head. A circle can't show rotation, so the
            // twitch and the droop both move these bodily instead.
            ForEach([-1.0, 1.0], id: \.self) { side in
                ZStack {
                    Circle()
                        .fill(
                            LinearGradient(colors: [palette.body, palette.shade],
                                           startPoint: .top, endPoint: .bottom)
                        )
                        .frame(width: 70, height: 70)
                    Circle()
                        .fill(palette.accent.opacity(0.55))
                        .frame(width: 36, height: 36)
                }
                .offset(x: side * (102 + twitch * side * 0.5), y: -26 + droop * 0.7)
            }
        }
    }

    // MARK: Face

    @ViewBuilder
    private func face(time: Double, liveliness: Double) -> some View {
        let openness = eyeOpenness(time: time)

        ZStack {
            // Cheeks — the blush appears as the pet gets happier.
            ForEach([-1.0, 1.0], id: \.self) { side in
                Circle()
                    .fill(Self.blush.opacity(0.12 + 0.28 * pet.moodScore))
                    .frame(width: 40, height: 30)
                    .blur(radius: 7)
                    .offset(x: side * 84, y: 30)
            }

            // Eyes. Below a certain openness a drawn lid reads far better than a
            // squashed eyeball, so the two are mutually exclusive.
            ForEach([-1.0, 1.0], id: \.self) { side in
                if openness >= 0.22 {
                    ZStack {
                        Ellipse()
                            .fill(.white)
                            .frame(width: 46, height: 46 * openness)
                        Circle()
                            .fill(Color.black.opacity(0.85))
                            .frame(width: 22 * min(openness * 1.4, 1), height: 22 * openness)
                            .offset(x: gaze.width * 7, y: gaze.height * 5)
                        Circle()
                            .fill(.white)
                            .frame(width: 6 * openness, height: 6 * openness)
                            .offset(x: gaze.width * 5 + 4, y: gaze.height * 4 - 5)
                    }
                    .offset(x: side * 48, y: -16)
                } else {
                    ClosedEyeShape()
                        .stroke(palette.shade, style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                        .frame(width: 42, height: 12)
                        .offset(x: side * 48, y: -14)
                }
            }

            // Nose — a rounded heart-ish blob reads better than a bare triangle.
            Triangle()
                .fill(pet.noseColor)
                .frame(width: 26, height: 16)
                .rotationEffect(.degrees(180))
                .clipShape(RoundedRectangle(cornerRadius: 5))
                .offset(y: 24)

            if pet.kind == .dog, pet.moodScore > 0.7 || isThrilled {
                // Tongue out when thrilled, tucked behind the mouth line.
                Capsule()
                    .fill(Self.tongue)
                    .frame(width: 20, height: 28)
                    .offset(y: 62)
            }

            // Mouth, curved by mood.
            MouthShape(curve: mouthCurve)
                .stroke(pet.noseColor.opacity(0.75),
                        style: StrokeStyle(lineWidth: 5, lineCap: .round))
                .frame(width: 56, height: 24)
                .offset(y: 48)

            if pet.kind == .cat {
                whiskers
            }

            if isSleepy {
                sleepZeds(time: time)
            }
        }
    }

    private var whiskers: some View {
        ForEach([-1.0, 1.0], id: \.self) { side in
            ForEach(0..<3, id: \.self) { index in
                Capsule()
                    .fill(palette.shade.opacity(0.55))
                    .frame(width: 46, height: 2.5)
                    .rotationEffect(.degrees(side * Double(index - 1) * 13))
                    .offset(x: side * 90, y: 32 + Double(index - 1) * 9)
            }
        }
    }

    private func sleepZeds(time: Double) -> some View {
        let phase = time.truncatingRemainder(dividingBy: 3) / 3
        return Text("z")
            .font(.system(size: 26, weight: .bold, design: .rounded))
            .foregroundStyle(palette.shade)
            .opacity(1 - phase)
            .offset(x: 90 + phase * 26, y: -80 - phase * 50)
    }

    // MARK: Expression maths

    /// Blinks roughly every four seconds, and squints when content.
    private func eyeOpenness(time: Double) -> Double {
        if isSleepy { return 0.08 }

        let cycle = time.truncatingRemainder(dividingBy: 4.3)
        let blink: Double = cycle < 0.18 ? abs(cycle - 0.09) / 0.09 : 1

        // Wide, pleading eyes while complaining, whatever the underlying mood.
        if isUpset { return max(blink, 0.05) }
        // Wider still when thrilled — a squint would waste the moment.
        if isThrilled { return max(blink, 0.05) }

        let base: Double
        switch pet.mood {
        case .ecstatic: base = isBeingPetted ? 0.25 : 0.7
        case .happy: base = isBeingPetted ? 0.35 : 0.85
        case .content: base = 0.9
        case .restless: base = 1.0
        case .sad: base = 0.85
        case .miserable: base = 0.6
        }
        return max(blink * base, 0.05)
    }

    private var mouthCurve: Double {
        if isUpset { return -0.8 }
        if isThrilled { return 1.0 }
        return switch pet.mood {
        case .ecstatic: 0.95
        case .happy: 0.7
        case .content: 0.35
        case .restless: 0.0
        case .sad: -0.5
        case .miserable: -0.85
        }
    }

    // MARK: Tail

    @ViewBuilder
    private func tail(time: Double, liveliness: Double) -> some View {
        switch pet.kind {
        case .cat, .dragon:
            let sway = sin(time * (1.6 + 2.5 * liveliness)) * (8 + 14 * liveliness)
            Capsule()
                .fill(
                    LinearGradient(colors: [palette.shade, palette.body],
                                   startPoint: .bottom, endPoint: .top)
                )
                // Negative angles swing the tip out to the right; positive would tuck
                // it behind the head where nobody can see it.
                .frame(width: 22, height: 140)
                .rotationEffect(.degrees(-42 + sway), anchor: .top)
                .offset(x: 92, y: 30)

        case .dog:
            let wag = sin(time * (4 + 9 * liveliness)) * (10 + 26 * liveliness)
            Capsule()
                .fill(palette.shade)
                .frame(width: 22, height: 104)
                .rotationEffect(.degrees(-38 + wag), anchor: .top)
                .offset(x: 90, y: 26)

        case .bunny:
            Circle()
                .fill(palette.belly)
                .frame(width: 48, height: 48)
                .offset(x: 112, y: 70)

        case .monkey:
            let curl = sin(time * (2.2 + 3.5 * liveliness)) * (5 + 12 * liveliness)
            CurledTailShape()
                .stroke(palette.shade,
                        style: StrokeStyle(lineWidth: 16, lineCap: .round))
                .frame(width: 118, height: 92)
                // Anchored at the left end, where the tail meets the body, so the sway
                // swings the hooked tip rather than sliding the whole tail sideways.
                .rotationEffect(.degrees(curl), anchor: .leading)
                .offset(x: 134, y: 74)
        }
    }
}

// MARK: - Shapes

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// A tail that sweeps down and away from the body, then hooks back up at the tip.
struct CurledTailShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY + rect.height * 0.18),
            control1: CGPoint(x: rect.minX + rect.width * 0.3, y: rect.maxY),
            control2: CGPoint(x: rect.maxX + rect.width * 0.12, y: rect.maxY)
        )
        return path
    }
}

/// A gentle downward arc, used for a sleeping or blissfully squinting eye.
struct ClosedEyeShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.maxY * 1.6)
        )
        return path
    }
}

/// A single curve whose bend runs from a deep frown (-1) to a wide smile (1).
struct MouthShape: Shape {
    var curve: Double

    var animatableData: Double {
        get { curve }
        set { curve = newValue }
    }

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.midY),
            control: CGPoint(x: rect.midX, y: rect.midY + rect.height * curve)
        )
        return path
    }
}
