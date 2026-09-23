import SwiftUI

/// The main screen: one pet, four needs, and a slab of glass you can stroke.
struct PetHomeView: View {
    @Environment(PetWorld.self) private var world

    @State private var lastTouch: CGPoint?
    @State private var gaze: CGSize = .zero
    @State private var isPlaying = false
    @State private var isCuddling = false
    @State private var isFeeding = false
    @State private var isShowingTricks = false
    /// Whether the needs are showing what they mean and what to do about them.
    @State private var isExplainingNeeds = false
    /// Unfolds the guide by itself until the owner has been through it once.
    @AppStorage("PetPhone.hasReadNeedsGuide") private var hasReadNeedsGuide = false

    var body: some View {
        ZStack {
            backdrop
            if let pet = world.pet {
                content(for: pet)
            }
        }
        .fullScreenCover(isPresented: $isPlaying) {
            PlaySessionView()
        }
        .fullScreenCover(isPresented: $isCuddling) {
            CuddleSessionView()
        }
        .fullScreenCover(isPresented: $isFeeding) {
            MealSessionView()
        }
        .sheet(isPresented: $isShowingTricks) {
            TrickBookView()
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
            // A trick asked for from the trick book is performed right here.
            .trickPose(trickPose)

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

    /// How the pet is held partway through a trick, or neutral when it isn't showing off.
    private var trickPose: TrickPose {
        guard let trick = world.showOff else { return .neutral }
        return world.showOffSucceeded
            ? .performing(trick, progress: world.showOffRoutine)
            : .fumbling(progress: world.showOffRoutine)
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
        // Asleep or out for the day beats anything the phone can tell us about itself.
        if let phaseSymbol = world.phaseSymbol { return phaseSymbol }
        if world.holdSensor.isFaceDown { return "iphone.slash" }
        if world.holdSensor.isSetDown { return "table.furniture" }
        if world.holdSensor.isHeld { return "hand.raised.fill" }
        return "iphone.gen3"
    }

    // MARK: Needs

    private func needsPanel(for pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                Text("Needs")
                    .font(.headline)
                Spacer(minLength: 0)
                Button {
                    toggleNeedsGuide()
                } label: {
                    Image(systemName: isExplainingNeeds ? "questionmark.circle.fill" : "questionmark.circle")
                        .font(.title3)
                        .foregroundStyle(pet.palette.accent)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(isExplainingNeeds ? "Hide what the needs mean" : "What do these needs mean?")
            }

            if isExplainingNeeds {
                // Explained, the four needs get a column each to themselves: the advice
                // is no use squeezed into half a phone's width.
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(NeedKind.allCases) { kind in
                        NeedMeter(kind: kind, value: pet.needs.value(for: kind), isExplaining: true)
                    }
                }
            } else {
                LazyVGrid(columns: [GridItem(spacing: 18), GridItem(spacing: 18)], spacing: 12) {
                    ForEach(NeedKind.allCases) { kind in
                        NeedMeter(kind: kind, value: pet.needs.value(for: kind), isExplaining: false)
                    }
                }
            }

            // Someone new to the app gets the guide unfolded for them, and a way to
            // fold it away once they have read it. After that it is opt-in.
            if !hasReadNeedsGuide {
                Divider().opacity(0.4)
                HStack(spacing: 10) {
                    Text("Every meter empties on its own. Keep them topped up and \(pet.name) stays happy.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    if isExplainingNeeds {
                        Button("Got it") { toggleNeedsGuide() }
                            .font(.caption.weight(.semibold))
                            .buttonStyle(.glass)
                            .buttonBorderShape(.capsule)
                    }
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 22))
        .onAppear {
            if !hasReadNeedsGuide { isExplainingNeeds = true }
        }
    }

    /// Folding the guide away counts as having read it, so it stops unfolding itself.
    private func toggleNeedsGuide() {
        withAnimation(.snappy(duration: 0.28)) {
            isExplainingNeeds.toggle()
            if !isExplainingNeeds { hasReadNeedsGuide = true }
        }
    }

    // MARK: Actions

    private var actions: some View {
        HStack(spacing: 12) {
            Button {
                // A stuffed pet turns the bowl down rather than opening a meal it can't eat.
                if world.canEat {
                    isFeeding = true
                } else {
                    world.declineFood()
                }
            } label: {
                actionLabel("Feed", symbol: "fork.knife")
            }
            .buttonStyle(.glassProminent)

            Button {
                // A tired pet says no rather than opening a game it won't take part in.
                if world.canPlay {
                    isPlaying = true
                } else {
                    world.declinePlay()
                }
            } label: {
                actionLabel("Play", symbol: "tennisball.fill")
            }
            .buttonStyle(.glass)

            Button {
                // A proper cuddle: stroke them drowsy, then tuck them in.
                isCuddling = true
            } label: {
                actionLabel("Cuddle", symbol: "heart.fill")
            }
            .buttonStyle(.glass)

            Button {
                // The trick book: teach a new one, practise an old one, or just ask.
                isShowingTricks = true
            } label: {
                actionLabel("Tricks", symbol: "pawprint.fill")
            }
            .buttonStyle(.glass)
        }
        .controlSize(.large)
    }

    /// Stacked icon and caption, so four buttons fit a narrow phone. The caption is
    /// allowed to shrink a little rather than truncate to "Cud…".
    private func actionLabel(_ title: String, symbol: String) -> some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.title3)
            Text(title)
                .font(.caption.weight(.semibold))
                .minimumScaleFactor(0.75)
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
    /// When true the meter also says what the need is for and how to top it up.
    let isExplaining: Bool

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
            if isExplaining {
                Text(kind.explanation)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 2)
                Label(kind.remedy, systemImage: kind.remedySymbolName)
                    .font(.caption2.weight(.medium))
                    .foregroundStyle(tint)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(kind.label)
        .accessibilityValue("\(Int(value * 100)) percent")
        .accessibilityHint(isExplaining ? "\(kind.explanation) \(kind.remedy)" : "")
    }
}

/// One heart (or crumb, or spark) drifting up off the pet and fading out.
struct FloatingSymbolView: View {
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
