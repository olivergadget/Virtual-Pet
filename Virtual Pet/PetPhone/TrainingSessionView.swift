import SwiftUI

/// A lesson. The pet watches your hands rather than your words, so each cue means
/// drawing the trick's hand signal on the glass — then saying well done before the pet
/// decides the whole thing was a coincidence.
struct TrainingSessionView: View {
    let trick: TrickKind

    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss

    @State private var session: TrainingSession

    init(trick: TrickKind) {
        self.trick = trick
        _session = State(initialValue: TrainingSession(trick: trick))
    }

    var body: some View {
        ZStack {
            if let pet = world.pet {
                arena(for: pet)
            }
        }
        .task {
            guard world.pet != nil else {
                dismiss()
                return
            }
            session.onAttempt = { world.attemptTrick($0) }
            session.onPraise = { world.praiseTrick($0) }
            session.onMuddle = { world.noteMuddledSignal() }
            world.beginTrainingSession(trick)
            let outcome = await session.run()
            world.endTrainingSession(outcome)
            dismiss()
        }
    }

    // MARK: Arena

    private func arena(for pet: Pet) -> some View {
        ZStack {
            LinearGradient(colors: pet.palette.sky, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            stage(for: pet)
        }
        .safeAreaInset(edge: .top) {
            cueCard(for: pet)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
        .safeAreaInset(edge: .bottom) {
            signalCard(for: pet)
                .padding(.horizontal, 20)
                .padding(.top, 6)
        }
    }

    /// The pet, and the whole surface the hand signal is drawn on.
    private func stage(for pet: Pet) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())

            VStack {
                Spacer()
                ZStack {
                    PetFaceView(pet: pet, isUpset: session.isMuddled)
                        .trickPose(session.pose)

                    ForEach(world.floatingSymbols) { item in
                        FloatingSymbolView(item: item, tint: pet.palette.accent)
                    }
                }
                .allowsHitTesting(false)
                Spacer()
                    .frame(height: 40)
            }
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in session.touch(at: value.location) }
                .onEnded { _ in session.liftFinger() }
        )
        .accessibilityElement()
        .accessibilityLabel("Training area")
        .accessibilityHint("Say \(trick.cue), then \(trick.signal.instruction). Pat \(pet.name) when it gets it right.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    // MARK: Cue card

    private func cueCard(for pet: Pet) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Label(trick.displayName, systemImage: trick.symbolName)
                    .font(.headline)
                    .foregroundStyle(pet.palette.accent)

                Spacer(minLength: 0)

                Text("Go \(session.rep) of \(TrainingTuning.repsPerSession)")
                    .font(.subheadline.weight(.semibold).monospacedDigit())

                Spacer(minLength: 0)

                Button("Done") { session.finish() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            Text(trick.cue)
                .font(.largeTitle.weight(.bold).width(.expanded))
                .foregroundStyle(session.isWaitingForSignal ? .primary : .secondary)
                .animation(.easeInOut(duration: 0.25), value: session.phase == .cue)

            ProgressView(value: world.pet?.mastery(of: trick) ?? 0)
                .progressViewStyle(.linear)
                .tint(pet.palette.accent)
                .accessibilityLabel("\(trick.displayName) mastery")
                .accessibilityValue(world.pet?.record(for: trick)?.masteryTitle ?? "Not yet")
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    // MARK: Signal card

    private func signalCard(for pet: Pet) -> some View {
        VStack(spacing: 8) {
            Text(hint(for: pet))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: session.phase)

            if session.isWaitingForSignal {
                HStack(spacing: 14) {
                    Label(trick.signal.name, systemImage: trick.signal.symbolName)
                        .font(.subheadline.weight(.semibold))
                        .labelStyle(.titleAndIcon)
                        .frame(width: 128, alignment: .leading)

                    SignalTrace(signal: trick.signal,
                                progress: session.signalProgress,
                                tint: pet.palette.accent)
                }
                .transition(.opacity)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 22))
        .animation(.easeInOut(duration: 0.25), value: session.isWaitingForSignal)
    }

    private func hint(for pet: Pet) -> String {
        switch session.phase {
        case .cue:
            if session.isMuddled {
                return "\(pet.name) has no idea what that was. Try the signal again."
            }
            return "Say \(trick.cue) out loud and \(trick.signal.instruction)."

        case .thinking:
            return "\(pet.name) is working out what you mean…"

        case .performing:
            return session.didSucceed ? "Here it comes!" : "That… wasn't it."

        case .praising:
            return session.wasPraised
                ? "Good \(pet.name)!"
                : "Got it! Pat \(pet.name) to say well done."

        case .fumbled:
            return "Not quite. \(pet.name) gets another go in a moment."
        }
    }
}

// MARK: - Signal trace

/// The hand signal drawn as a dashed guide with a dot running along it, filling in as the
/// signal is drawn, so the movement can be copied without reading anything twice.
private struct SignalTrace: View {
    let signal: HandSignal
    /// 0...1, how much of the signal has been drawn so far.
    let progress: Double
    let tint: Color

    /// How long the dot takes to run the guide once.
    private static let loop: TimeInterval = 1.9

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30.0)) { context in
            let phase = context.date.timeIntervalSinceReferenceDate
                .truncatingRemainder(dividingBy: Self.loop) / Self.loop

            GeometryReader { proxy in
                let guide = signal.guidePath(in: proxy.size)
                ZStack {
                    guide
                        .stroke(tint.opacity(0.30),
                                style: StrokeStyle(lineWidth: 4, lineCap: .round, dash: [7, 8]))

                    guide
                        .trimmedPath(from: 0, to: max(progress, 0.0001))
                        .stroke(tint, style: StrokeStyle(lineWidth: 5, lineCap: .round))

                    if let dot = guide.trimmedPath(from: 0, to: max(phase, 0.0001)).currentPoint {
                        Circle()
                            .fill(tint)
                            .frame(width: 15, height: 15)
                            .position(dot)
                    }
                }
            }
        }
        .frame(height: 68)
        .accessibilityHidden(true)
    }
}
