import SwiftUI

/// The reunion. Two pets spot each other across the room, sprint into a collision, and
/// then completely lose it — bouncing, spinning, shrieking, with fireworks going off
/// behind them and a banner that would embarrass a film trailer.
struct ReunionView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss

    let cast: ReunionCast

    @State private var show = Reunion()

    /// The other pet, built once from its card rather than on every frame.
    private let friend: Pet

    init(cast: ReunionCast) {
        self.cast = cast
        self.friend = cast.stageDouble
    }

    var body: some View {
        ZStack {
            if let pet = world.pet {
                stage(for: pet)
            }
        }
        .task {
            guard world.pet != nil else {
                dismiss()
                return
            }
            show.onCue = { cue in
                world.reunionCue(cue, friend: cast.friend)
            }
            world.beginReunion(cast)
            await show.run()
            world.endReunion(cast)
            dismiss()
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(headline)
        .accessibilityHint("Tap anywhere to skip the celebration")
    }

    // MARK: Stage

    private func stage(for pet: Pet) -> some View {
        ZStack {
            backdrop(for: pet)

            ZStack {
                beams
                particleLayer
                performers(for: pet)
            }
            // The whole stage jolts on impact and every burst.
            .offset(x: sin(show.elapsed * 71) * show.shake * 11,
                    y: cos(show.elapsed * 63) * show.shake * 9)

            Color.white
                .opacity(show.flash * 0.75)
                .blendMode(.plusLighter)
                .ignoresSafeArea()
                .allowsHitTesting(false)

            banner
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            show.setStage(size)
        }
        .contentShape(Rectangle())
        .onTapGesture {
            show.skip()
        }
        .safeAreaInset(edge: .top) {
            marquee(for: pet)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
    }

    /// The two pets' skies, shoved together into one.
    private func backdrop(for pet: Pet) -> some View {
        LinearGradient(
            colors: [
                pet.palette.sky.first ?? pet.palette.body,
                friend.palette.sky.last ?? friend.palette.body
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
        .ignoresSafeArea()
        .overlay {
            RadialGradient(colors: [.white.opacity(0.3 * show.glory), .clear],
                           center: .center, startRadius: 20, endRadius: 340)
                .ignoresSafeArea()
        }
    }

    /// Rotating sunbeams, because a moment like this deserves them.
    private var beams: some View {
        ZStack {
            ForEach(0..<14, id: \.self) { index in
                Capsule()
                    .fill(.white.opacity(0.32))
                    .frame(width: 26, height: 560)
                    .offset(y: -280)
                    .rotationEffect(.degrees(Double(index) / 14 * 360))
            }
        }
        .rotationEffect(.degrees(show.elapsed * 15))
        .scaleEffect(0.55 + 0.5 * show.glory)
        .opacity(show.glory * 0.9)
        .blendMode(.plusLighter)
        .allowsHitTesting(false)
    }

    // MARK: Pets

    private func performers(for pet: Pet) -> some View {
        ZStack {
            performer(pet: friend, state: show.theirs, other: show.mine.position, isMirrored: true)
            performer(pet: pet, state: show.mine, other: show.theirs.position, isMirrored: false)
        }
    }

    /// One pet, drawn at full size and scaled down so its shapes stay crisp. The mirrored
    /// one is flipped horizontally, so the two of them face each other.
    private func performer(pet: Pet, state: Reunion.Performer,
                           other: CGPoint, isMirrored: Bool) -> some View {
        PetFaceView(pet: pet, excitement: 1, gaze: gaze(from: state, to: other, isMirrored: isMirrored),
                    isThrilled: true)
            .frame(width: 280, height: 300)
            .scaleEffect(ReunionTuning.performerScale * state.scale)
            .frame(width: 280 * ReunionTuning.performerScale,
                   height: 300 * ReunionTuning.performerScale)
            .scaleEffect(x: state.squash * (isMirrored ? -1 : 1),
                         y: 2 - state.squash, anchor: .bottom)
            .rotationEffect(.degrees(state.rotation))
            .position(x: state.position.x, y: state.position.y - state.lift)
            .allowsHitTesting(false)
    }

    /// Eyes locked on the other pet. A mirrored pet's horizontal gaze has to be flipped
    /// back, or it stares off in the wrong direction.
    private func gaze(from state: Reunion.Performer, to other: CGPoint,
                      isMirrored: Bool) -> CGSize {
        let horizontal = min(max((other.x - state.position.x) / 130, -1), 1)
        let vertical = min(max((other.y - state.position.y) / 130, -1), 1)
        return CGSize(width: isMirrored ? -horizontal : horizontal, height: vertical)
    }

    // MARK: Particles

    /// Every spark, streamer and heart in one canvas. Symbols are resolved once per frame
    /// by tag rather than filtered per particle.
    private var particleLayer: some View {
        Canvas { context, _ in
            for particle in show.particles {
                switch particle.style {
                case .spark:
                    let radius = particle.size * (1 - particle.age * 0.5)
                    context.blendMode = .plusLighter
                    context.fill(
                        Path(ellipseIn: CGRect(x: particle.position.x - radius,
                                               y: particle.position.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(Self.colour(for: particle).opacity(particle.fade))
                    )
                    context.blendMode = .normal

                case .streak:
                    let speed = hypot(particle.velocity.width, particle.velocity.height)
                    let length = max(speed * 0.035, particle.size)
                    let body = Path(
                        roundedRect: CGRect(x: -length / 2, y: -particle.size / 2,
                                            width: length, height: particle.size),
                        cornerRadius: particle.size / 2
                    )
                    let transform = CGAffineTransform(
                        translationX: particle.position.x, y: particle.position.y
                    )
                    .rotated(by: atan2(particle.velocity.height, particle.velocity.width))
                    context.blendMode = .plusLighter
                    context.fill(body.applying(transform),
                                 with: .color(Self.colour(for: particle).opacity(particle.fade)))
                    context.blendMode = .normal

                case .confetti:
                    let paper = Path(
                        roundedRect: CGRect(x: -particle.size / 2, y: -particle.size / 4,
                                            width: particle.size, height: particle.size / 2),
                        cornerRadius: 2
                    )
                    let transform = CGAffineTransform(
                        translationX: particle.position.x, y: particle.position.y
                    )
                    .rotated(by: .pi / 180 * particle.angle)
                    context.fill(paper.applying(transform),
                                 with: .color(Self.colour(for: particle).opacity(particle.fade)))

                case .ring:
                    let radius = max(particle.size, 1)
                    context.blendMode = .plusLighter
                    context.stroke(
                        Path(ellipseIn: CGRect(x: particle.position.x - radius,
                                               y: particle.position.y - radius,
                                               width: radius * 2, height: radius * 2)),
                        with: .color(.white.opacity(particle.fade * 0.8)),
                        lineWidth: particle.lineWidth
                    )
                    context.blendMode = .normal

                case .glyph(let glyph):
                    guard let symbol = context.resolveSymbol(id: glyph.rawValue) else { break }
                    let scale = particle.size / max(symbol.size.width, 1)
                    let width = symbol.size.width * scale
                    let height = symbol.size.height * scale
                    context.opacity = particle.fade
                    context.draw(symbol, in: CGRect(x: particle.position.x - width / 2,
                                                    y: particle.position.y - height / 2,
                                                    width: width, height: height))
                    context.opacity = 1
                }
            }
        } symbols: {
            ForEach(ReunionGlyph.allCases, id: \.self) { glyph in
                Image(systemName: glyph.symbolName)
                    .font(.system(size: 44, weight: .black))
                    .foregroundStyle(glyph.tint)
                    .tag(glyph.rawValue)
            }
        }
        .allowsHitTesting(false)
    }

    private static func colour(for particle: Reunion.Particle) -> Color {
        Color(hue: particle.hue, saturation: 0.85, brightness: 1)
    }

    // MARK: Titles

    private var isFinale: Bool {
        show.beat == .finale || show.beat == .over
    }

    private var banner: some View {
        VStack(spacing: 2) {
            Text(cast.isFirstMeeting ? "BEST FRIENDS" : "REUNITED")
                .font(.system(size: 42, weight: .black, design: .rounded).width(.expanded))
            Text(cast.isFirstMeeting ? "FOREVER!!!" : "AT LAST!!!")
                .font(.system(size: 38, weight: .black, design: .rounded).width(.expanded))
            Text(subtitle)
                .font(.footnote.weight(.bold))
                .foregroundStyle(.white.opacity(0.9))
                .padding(.top, 6)
        }
        .minimumScaleFactor(0.5)
        .lineLimit(1)
        .multilineTextAlignment(.center)
        .foregroundStyle(
            LinearGradient(colors: [.white, Color(red: 1, green: 0.86, blue: 0.35)],
                           startPoint: .top, endPoint: .bottom)
        )
        .shadow(color: .black.opacity(0.35), radius: 10, y: 6)
        .padding(.horizontal, 24)
        .rotationEffect(.degrees(-4))
        .scaleEffect(isFinale ? 1 : 0.4)
        .opacity(isFinale ? 1 : 0)
        .offset(y: 118)
        .animation(.spring(response: 0.4, dampingFraction: 0.42), value: isFinale)
        .allowsHitTesting(false)
    }

    private var subtitle: String {
        if cast.isFirstMeeting {
            return "\(headline) · FRIENDS AT FIRST SIGHT"
        }
        return "\(headline) · \(cast.bondTitle.uppercased()) · MEETING \(cast.meetings)"
    }

    private var headline: String {
        "\(world.pet?.name ?? "Your pet") + \(cast.friend.name)"
    }

    /// A small strip at the top naming the two of them, plus the way out.
    private func marquee(for pet: Pet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: pet.kind.symbolName)
                .foregroundStyle(pet.palette.accent)
            Text(headline)
                .font(.subheadline.weight(.bold))
                .lineLimit(1)
            Image(systemName: cast.friend.kind.symbolName)
                .foregroundStyle(friend.palette.accent)

            Spacer(minLength: 0)

            Button("Skip") { show.skip() }
                .buttonStyle(.glass)
                .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .glassEffect(in: .rect(cornerRadius: 20))
    }
}

#Preview {
    // The show needs a pet of its own to put on the stage, so the preview adopts one if
    // this device hasn't got one yet.
    if !PetWorld.shared.hasPet {
        PetWorld.shared.adopt(name: "Mochi", kind: .cat)
    }
    return ReunionView(cast: ReunionCast(
        friend: PetCard(id: UUID().uuidString, name: "Waffle", kind: .dog,
                        level: 3, moodLabel: "Over the moon",
                        headline: "Level 3 · Attached · Over the moon"),
        meetings: 1,
        bondTitle: "Sniffing distance"
    ))
    .environment(PetWorld.shared)
}
