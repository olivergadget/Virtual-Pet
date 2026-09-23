import SwiftUI

/// The cuddle. Stroke the pet until it is drowsy, then drag the blanket up over it and
/// let go to tuck it in.
struct CuddleSessionView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss

    @State private var cuddle = CuddleSession()

    var body: some View {
        ZStack {
            if let pet = world.pet {
                den(for: pet)
            }
        }
        .task {
            guard world.pet != nil else {
                dismiss()
                return
            }
            // Calm stroking is the same act as petting on the home screen, so it runs
            // through the same purring, hearts and affection — and only while it stays calm.
            cuddle.onSoothingBegan = { world.beginPetting() }
            cuddle.onStroke = { travelled in world.continuePetting(speed: travelled) }
            cuddle.onSoothingEnded = { world.endPetting() }
            cuddle.onSleepy = { world.noteCuddleSleepy() }
            cuddle.onTucked = { world.recordTuckIn() }
            cuddle.onFuss = { world.noteCuddleFuss() }

            world.beginCuddleSession()
            let outcome = await cuddle.run()
            world.endCuddleSession(warmth: outcome.warmth, tucked: outcome.tucked)
            dismiss()
        }
    }

    // MARK: Den

    private func den(for pet: Pet) -> some View {
        ZStack {
            LinearGradient(colors: pet.palette.sky, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .overlay {
                    // The room dims as the pet drifts off.
                    Color.black
                        .opacity(0.28 * cuddle.warmth)
                        .ignoresSafeArea()
                        .animation(.easeInOut(duration: 0.5), value: cuddle.warmth)
                }

            floor(for: pet)
        }
        .safeAreaInset(edge: .top) {
            banner(for: pet)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
    }

    /// Everything inside is positioned in the floor's own coordinates, which is what
    /// `CuddleSession` works in.
    private func floor(for pet: Pet) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())

            petSprite(for: pet)

            // Rising from just above the head, so hearts and grumbles never sit on the face.
            ForEach(world.floatingSymbols) { item in
                FloatingSymbolView(item: item, tint: pet.palette.accent)
                    .position(x: cuddle.petFrame.midX, y: cuddle.petFrame.minY)
            }

            blanket(for: pet)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            cuddle.setArena(size)
        }
        .accessibilityElement()
        .accessibilityLabel("Cuddle area")
        .accessibilityHint(accessibilityHint(for: pet))
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func petSprite(for pet: Pet) -> some View {
        PetFaceView(
            pet: pet,
            isBeingPetted: cuddle.isStroking,
            excitement: world.pettingIntensity,
            gaze: cuddle.gaze,
            isUpset: cuddle.isFussing
        )
        .frame(width: 280, height: 300)
        // A grumbling pet tips its head at you until you get on with it.
        .rotationEffect(.degrees(cuddle.isFussing ? 4 : 0))
        .animation(.spring(duration: 0.35), value: cuddle.isFussing)
        // Drawn at full size and scaled down, so the shapes stay crisp.
        .scaleEffect(CuddleTuning.petSize.width / 280)
        .frame(width: CuddleTuning.petSize.width, height: CuddleTuning.petSize.height)
        // Sinking into the blanket once tucked in.
        .scaleEffect(1 - 0.05 * cuddle.snug, anchor: .bottom)
        .offset(y: 10 * cuddle.snug)
        .position(x: cuddle.petFrame.midX, y: cuddle.petFrame.midY)
        .contentShape(Rectangle())
        .gesture(strokeGesture, isEnabled: cuddle.phase == .stroking)
    }

    private var strokeGesture: some Gesture {
        // A zero-distance drag means a resting finger already counts as contact.
        DragGesture(minimumDistance: 0)
            .onChanged { value in cuddle.stroke(at: value.location) }
            .onEnded { _ in cuddle.liftFinger() }
    }

    // MARK: Blanket

    private func blanket(for pet: Pet) -> some View {
        let frame = cuddle.blanketFrame
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: 38,
            bottomLeadingRadius: 0,
            bottomTrailingRadius: 0,
            topTrailingRadius: 38
        )

        return shape
            .fill(
                LinearGradient(
                    colors: [pet.palette.accent, pet.palette.shade],
                    startPoint: .top,
                    endPoint: .bottom
                )
            )
            .overlay { quilting.clipShape(shape) }
            .overlay(alignment: .top) { hem }
            .shadow(color: .black.opacity(0.3), radius: 14, y: -6)
            .frame(width: frame.width, height: frame.height)
            .position(x: frame.midX, y: frame.midY)
            // Until the pet is sleepy the blanket is just scenery.
            .opacity(cuddle.canTuck || cuddle.isTucked ? 1 : 0.65)
            .gesture(blanketGesture, isEnabled: cuddle.canTuck)
            .animation(.easeInOut(duration: 0.4), value: cuddle.canTuck)
    }

    private var blanketGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                cuddle.grabBlanket()
                cuddle.dragBlanket(by: value.translation.height)
            }
            .onEnded { _ in cuddle.releaseBlanket() }
    }

    /// The folded-over top edge, with a grab handle so it reads as draggable.
    private var hem: some View {
        VStack(spacing: 8) {
            Capsule()
                .fill(.white.opacity(0.55))
                .frame(width: 54, height: 5)
            if cuddle.canTuck, !cuddle.isDraggingBlanket {
                Image(systemName: "chevron.up")
                    .font(.footnote.weight(.bold))
                    .foregroundStyle(.white.opacity(0.8))
                    .symbolEffect(.bounce, options: .repeating)
            }
        }
        .padding(.top, 12)
        .frame(maxWidth: .infinity)
        .background(alignment: .top) {
            Rectangle()
                .fill(.white.opacity(0.18))
                .frame(height: 34)
        }
        .clipShape(UnevenRoundedRectangle(topLeadingRadius: 38, topTrailingRadius: 38))
        .allowsHitTesting(false)
    }

    /// Two sets of crossed stitching, oversized so the rotated stripes still fill the shape.
    private var quilting: some View {
        ZStack {
            stitches(angle: 34)
            stitches(angle: -34)
        }
        .opacity(0.22)
    }

    private func stitches(angle: Double) -> some View {
        HStack(spacing: 38) {
            ForEach(0..<14, id: \.self) { _ in
                Rectangle()
                    .fill(.white)
                    .frame(width: 2)
            }
        }
        .rotationEffect(.degrees(angle))
        .scaleEffect(2.2)
    }

    // MARK: Banner

    private func banner(for pet: Pet) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Label(cuddle.phase == .stroking ? "Stroke" : "Tuck in",
                      systemImage: cuddle.phase == .stroking ? "hand.draw.fill" : "bed.double.fill")
                    .font(.headline)
                    .foregroundStyle(pet.palette.accent)

                Spacer(minLength: 0)

                Button("Done") { cuddle.finish() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            ProgressView(value: cuddle.phase == .stroking ? cuddle.warmth : cuddle.coverage)
                .progressViewStyle(.linear)
                .tint(pet.palette.accent)
                .animation(.easeOut(duration: 0.2), value: cuddle.warmth)
                .accessibilityLabel(cuddle.phase == .stroking ? "Sleepiness" : "Blanket coverage")

            Text(hint(for: pet))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: cuddle.phase)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    private func hint(for pet: Pet) -> String {
        switch cuddle.phase {
        case .stroking:
            if !cuddle.hasStroked {
                return "Stroke \(pet.name) with your finger to settle them."
            }
            if cuddle.isTooRough {
                return "Too fast! \(pet.name) wants slow, gentle strokes."
            }
            if cuddle.isFussing {
                return "\(pet.name) is grumbling at you. Don't stop."
            }
            if !cuddle.isSoothing {
                return "Keep your hand moving — slow circles."
            }
            return "\(pet.name) is going drowsy..."

        case .tucking:
            if cuddle.isDraggingBlanket {
                return cuddle.isCoveringPet
                    ? "Let go to tuck \(pet.name) in."
                    : "Higher — cover \(pet.name) up."
            }
            if cuddle.hasLostBlanket {
                return "The blanket came off! \(pet.name) wants it back."
            }
            return "\(pet.name) is sleepy. Pull the blanket up over them."

        case .settled:
            return "Tucked in. Goodnight, \(pet.name)."
        }
    }

    private func accessibilityHint(for pet: Pet) -> String {
        switch cuddle.phase {
        case .stroking: "Drag across \(pet.name) to stroke them until they are sleepy."
        case .tucking: "Drag the blanket up from the bottom of the screen to cover \(pet.name), then let go."
        case .settled: "\(pet.name) is tucked in."
        }
    }
}
