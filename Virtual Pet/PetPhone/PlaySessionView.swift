import SwiftUI

/// The play session. A toy trails your fingertip and the pet only chases it while it is
/// moving, so you have to keep flicking it about *and* steer it within pouncing distance.
struct PlaySessionView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss

    @State private var chase = ToyChase()

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
            chase.onCatch = { world.recordCatch() }
            world.beginPlaySession()
            let catches = await chase.run()
            world.endPlaySession(catches: catches)
            dismiss()
        }
    }

    // MARK: Arena

    private func arena(for pet: Pet) -> some View {
        ZStack {
            LinearGradient(colors: pet.palette.sky, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            field(for: pet)
        }
        .safeAreaInset(edge: .top) {
            scoreboard(for: pet)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
    }

    /// The playing surface. Everything inside is positioned in the field's own
    /// coordinates, which is what `ToyChase` works in.
    private func field(for pet: Pet) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())

            petSprite(for: pet)
            toySprite(for: pet)
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            chase.setArena(size)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in chase.moveToy(to: value.location) }
                .onEnded { _ in chase.liftFinger() }
        )
        .accessibilityElement()
        .accessibilityLabel("Play area")
        .accessibilityHint("Drag the \(pet.kind.toyName) around. \(pet.name) chases it only while it moves.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private func petSprite(for pet: Pet) -> some View {
        // The eyes track the toy; the lean and the pounce squash do the running.
        PetFaceView(pet: pet, gaze: chase.gaze)
            .frame(width: 280, height: 300)
            // Drawn at full size and scaled down, so the shapes stay crisp.
            .scaleEffect(0.4 * (1 + 0.16 * chase.celebration))
            .frame(width: 112, height: 120)
            .rotationEffect(.degrees(chase.lean))
            .position(chase.petPosition)
            .allowsHitTesting(false)
    }

    private func toySprite(for pet: Pet) -> some View {
        ZStack {
            Circle()
                .stroke(pet.kind.toyColor.opacity(0.45 * chase.liveliness), lineWidth: 3)
                .frame(width: 52 + 18 * chase.liveliness, height: 52 + 18 * chase.liveliness)

            Image(systemName: pet.kind.toySymbol)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(pet.kind.toyColor)
                .shadow(color: pet.kind.toyColor.opacity(0.7), radius: 8 + 10 * chase.liveliness)
                .scaleEffect(1 + 0.18 * chase.liveliness)
        }
        .position(chase.toy)
        .allowsHitTesting(false)
    }

    // MARK: Scoreboard

    private func scoreboard(for pet: Pet) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 12) {
                Label("\(chase.catches)", systemImage: pet.kind.toySymbol)
                    .font(.headline.monospacedDigit())
                    .foregroundStyle(pet.kind.toyColor)
                    .accessibilityLabel("\(chase.catches) catches")

                Spacer(minLength: 0)

                Label("\(Int(chase.timeRemaining.rounded(.up)))s", systemImage: "timer")
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .accessibilityLabel("\(Int(chase.timeRemaining.rounded(.up))) seconds left")

                Spacer(minLength: 0)

                Button("Done") { chase.finish() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            Text(hint(for: pet))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: chase.isChasing)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    private func hint(for pet: Pet) -> String {
        if chase.isCelebrating {
            return "Caught it! Flick the \(pet.kind.toyName) away again."
        }
        if !chase.hasStarted {
            return "Drag the \(pet.kind.toyName) — \(pet.name) only chases it while it moves."
        }
        if !chase.isChasing {
            return "\(pet.name) has lost interest. Keep it moving!"
        }
        return "Steer it close enough to be caught!"
    }
}
