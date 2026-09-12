import SwiftUI

/// The main screen: one pet, four needs, and a slab of glass you can stroke.
struct PetHomeView: View {
    @Environment(PetWorld.self) private var world

    @State private var lastTouch: CGPoint?
    @State private var gaze: CGSize = .zero

    var body: some View {
        ZStack {
            backdrop
            if let pet = world.pet {
                content(for: pet)
            }
        }
    }

    // MARK: Background

    @ViewBuilder
    private var backdrop: some View {
        if let pet = world.pet {
            LinearGradient(colors: pet.palette.sky, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()
                .overlay {
                    RadialGradient(
                        colors: [.white.opacity(world.isBeingPetted ? 0.35 : 0.12), .clear],
                        center: .center,
                        startRadius: 10,
                        endRadius: 320
                    )
                    .ignoresSafeArea()
                    .animation(.easeInOut(duration: 0.6), value: world.isBeingPetted)
                }
        } else {
            Color.clear
        }
    }

    // MARK: Content

    private func content(for pet: Pet) -> some View {
        ScrollView {
            VStack(spacing: 22) {
                header(for: pet)
                stage(for: pet)
                statusPill(for: pet)
                needsPanel(for: pet)
                if let homeStatus = world.locator.homeStatus(for: pet) {
                    footnote(homeStatus, symbol: "house.fill")
                }
                if !world.social.nearby.isEmpty {
                    nearbyStrip
                }
            }
            .padding(.horizontal, 20)
            .padding(.top, 8)
            .padding(.bottom, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        // Pinned rather than scrolled: feeding your pet should never be off-screen.
        .safeAreaInset(edge: .bottom) {
            actions
                .padding(.horizontal, 20)
                .padding(.vertical, 8)
        }
    }

    private func header(for pet: Pet) -> some View {
        VStack(spacing: 4) {
            Text(pet.name)
                .font(.largeTitle.weight(.bold).width(.expanded))
            Text("\(pet.mood.emoji) \(pet.mood.label) · Level \(pet.level) · \(pet.levelTitle)")
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
            ProgressView(value: pet.progressToNextLevel)
                .progressViewStyle(.linear)
                .tint(pet.palette.accent)
                .frame(maxWidth: 180)
                .accessibilityLabel("Bond progress to the next level")
        }
        .padding(.top, 4)
    }

    /// The petting surface. A zero-distance drag means a resting finger counts as contact.
    private func stage(for pet: Pet) -> some View {
        ZStack {
            PetFaceView(
                pet: pet,
                isBeingPetted: world.isBeingPetted,
                isHeld: world.holdSensor.isHeld,
                excitement: world.pettingIntensity,
                gaze: gaze
            )

            ForEach(world.floatingSymbols) { item in
                FloatingSymbolView(item: item, tint: pet.palette.accent)
            }

            if let speech = world.speech {
                Text(speech)
                    .font(.callout.weight(.medium))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 10)
                    .frame(maxWidth: 260)
                    .glassEffect(in: .rect(cornerRadius: 20))
                    .offset(y: -122)
                    .transition(.scale(scale: 0.8).combined(with: .opacity))
            }
        }
        .frame(height: 308)
        .contentShape(Rectangle())
        .gesture(pettingGesture)
        .animation(.spring(duration: 0.35), value: world.speech)
        .accessibilityElement()
        .accessibilityLabel("\(pet.name), \(pet.mood.label)")
        .accessibilityHint("Drag to stroke your pet")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    private var pettingGesture: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !world.isBeingPetted {
                    world.beginPetting()
                }
                let point = value.location
                if let lastTouch {
                    let dx = point.x - lastTouch.x
                    let dy = point.y - lastTouch.y
                    world.continuePetting(speed: (dx * dx + dy * dy).squareRoot())
                }
                lastTouch = point
                gaze = CGSize(
                    width: min(max((point.x - 140) / 140, -1), 1),
                    height: min(max((point.y - 165) / 165, -1), 1)
                )
            }
            .onEnded { _ in
                lastTouch = nil
                withAnimation(.easeOut(duration: 0.5)) { gaze = .zero }
                world.endPetting()
            }
    }

    private func statusPill(for pet: Pet) -> some View {
        HStack(spacing: 8) {
            Image(systemName: holdSymbol)
                .foregroundStyle(pet.palette.accent)
            Text(world.statusLine)
                .font(.subheadline.weight(.medium))
                .multilineTextAlignment(.leading)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .glassEffect(in: .rect(cornerRadius: 18))
    }

    private var holdSymbol: String {
        if world.isBeingPetted { return "hand.draw.fill" }
        if world.holdSensor.isFaceDown { return "iphone.slash" }
        if world.holdSensor.isSetDown { return "table.furniture" }
        if world.holdSensor.isHeld { return "hand.raised.fill" }
        return "iphone.gen3"
    }

    // MARK: Needs

    private func needsPanel(for pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Needs")
                .font(.headline)
            LazyVGrid(columns: [GridItem(spacing: 18), GridItem(spacing: 18)], spacing: 12) {
                ForEach(NeedKind.allCases) { kind in
                    NeedMeter(kind: kind, value: pet.needs.value(for: kind))
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                world.feed()
            } label: {
                actionLabel("Feed", symbol: "fork.knife")
            }
            .buttonStyle(.glassProminent)

            Button {
                world.playTogether()
            } label: {
                actionLabel("Play", symbol: "tennisball.fill")
            }
            .buttonStyle(.glass)

            Button {
                world.quickCuddle()
            } label: {
                actionLabel("Cuddle", symbol: "heart.fill")
            }
            .buttonStyle(.glass)
        }
        .controlSize(.large)
    }

    /// Stacked icon and caption, so three buttons fit a narrow phone without truncating.
    private func actionLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.semibold))
        }
        .lineLimit(1)
        .frame(maxWidth: .infinity)
        .padding(.vertical, 4)
    }

    private func footnote(_ text: String, symbol: String) -> some View {
        HStack(spacing: 8) {
            Image(systemName: symbol)
            Text(text)
            Spacer(minLength: 0)
        }
        .font(.footnote)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    // MARK: Nearby

    private var nearbyStrip: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("Pets nearby", systemImage: "dot.radiowaves.left.and.right")
                .font(.headline)
            ScrollView(.horizontal) {
                HStack(spacing: 10) {
                    ForEach(world.social.nearby) { card in
                        VStack(spacing: 6) {
                            Image(systemName: card.kind.symbolName)
                                .font(.title2)
                                .foregroundStyle(card.kind.palette.accent)
                            Text(card.name)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(width: 82, height: 76)
                        .glassEffect(in: .rect(cornerRadius: 16))
                    }
                }
                .padding(.vertical, 2)
            }
            .scrollIndicators(.hidden)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: - Pieces

private struct NeedMeter: View {
    let kind: NeedKind
    let value: Double

    private var tint: Color {
        switch value {
        case 0.6...: .green
        case 0.3..<0.6: .orange
        default: .red
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 5) {
                Image(systemName: kind.symbolName)
                    .font(.caption2)
                    .foregroundStyle(tint)
                Text(kind.label)
                    .font(.caption.weight(.semibold))
                Spacer(minLength: 0)
                Text("\(Int(value * 100))%")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.label)
        .accessibilityValue("\(Int(value * 100)) percent")
    }
}

/// One heart (or crumb, or spark) drifting up off the pet and fading out.
private struct FloatingSymbolView: View {
    let item: FloatingSymbol
    let tint: Color

    @State private var progress: Double = 0

    var body: some View {
        Image(systemName: item.symbol)
            .font(.system(size: 26 * item.scale, weight: .semibold))
            .foregroundStyle(tint)
            .offset(x: item.horizontal * 72, y: -progress * 160)
            .opacity(1 - progress)
            .scaleEffect(0.5 + progress * 0.9)
            .allowsHitTesting(false)
            .onAppear {
                withAnimation(.easeOut(duration: 1.6)) { progress = 1 }
            }
    }
}
