import SwiftUI

/// The feeding session. You press and hold a bag of food to tip it, aim the stream into
/// the bowl with your fingertip, and then watch the pet come over and work through it.
struct MealSessionView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss

    @State private var meal = MealSession()

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
            meal.onBite = { world.recordBite() }
            meal.onPour = { world.recordFoodInBowl() }
            meal.onSpill = { world.recordSpill() }
            world.beginMealSession()
            let outcome = await meal.run()
            world.endMealSession(outcome)
            dismiss()
        }
    }

    // MARK: Arena

    private func arena(for pet: Pet) -> some View {
        ZStack {
            LinearGradient(colors: pet.palette.sky, startPoint: .top, endPoint: .bottom)
                .ignoresSafeArea()

            room(for: pet)
        }
        .safeAreaInset(edge: .top) {
            scoreboard(for: pet)
                .padding(.horizontal, 20)
                .padding(.bottom, 6)
        }
    }

    /// Everything inside is positioned in the room's own coordinates, which is what
    /// `MealSession` works in.
    private func room(for pet: Pet) -> some View {
        ZStack {
            Color.clear
                .contentShape(Rectangle())

            if meal.arena != .zero {
                floor(for: pet)
                spilledFood(for: pet)
                // The pet is drawn before the bowl so its muzzle dips down behind the rim.
                petSprite(for: pet)
                bowl(for: pet)
                fallingFood(for: pet)
                bagSprite(for: pet)
            }
        }
        .onGeometryChange(for: CGSize.self) { proxy in
            proxy.size
        } action: { size in
            meal.setArena(size)
        }
        .gesture(
            DragGesture(minimumDistance: 0)
                .onChanged { value in meal.moveBag(to: value.location) }
                .onEnded { _ in meal.liftFinger() }
        )
        .accessibilityElement()
        .accessibilityLabel("Feeding area")
        .accessibilityHint("Press and hold to tip the bag, and drag to aim the food into the bowl.")
        .accessibilityAddTraits(.allowsDirectInteraction)
    }

    // MARK: Room

    private func floor(for pet: Pet) -> some View {
        // Deliberately taller and wider than the room, so it runs off the bottom of the
        // screen rather than stopping at the edge of the safe area.
        let height = max(meal.arena.height - meal.floorY, 0) + 220

        return ZStack(alignment: .top) {
            Rectangle()
                .fill(
                    LinearGradient(
                        colors: [pet.palette.shade.opacity(0.34), pet.palette.shade.opacity(0.12)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
            Rectangle()
                .fill(.white.opacity(0.28))
                .frame(height: 2)
        }
        .frame(width: meal.arena.width + 40, height: height)
        .position(x: meal.arena.width / 2, y: meal.floorY + height / 2)
        .allowsHitTesting(false)
    }

    private func bowl(for pet: Pet) -> some View {
        let rimHeight = MealTuning.bowlHeight * MealTuning.bowlRimRatio
        let rimY = -MealTuning.bowlHeight / 2 + rimHeight / 2

        return ZStack {
            // The inside of the bowl, showing through wherever the food doesn't reach.
            Ellipse()
                .fill(
                    LinearGradient(colors: [.black.opacity(0.34), .black.opacity(0.16)],
                                   startPoint: .top, endPoint: .bottom)
                )
                .frame(width: MealTuning.bowlWidth - 14, height: rimHeight)
                .offset(y: rimY)

            if meal.bowlFill > 0 {
                heap(for: pet, rimY: rimY)
            }

            BowlShape()
                .fill(
                    LinearGradient(
                        colors: [.white.opacity(0.92), pet.palette.shade.opacity(0.55)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .overlay {
                    BowlShape()
                        .stroke(.white.opacity(0.55), lineWidth: 1.5)
                }
                .frame(width: MealTuning.bowlWidth, height: MealTuning.bowlHeight)
                .shadow(color: .black.opacity(0.2), radius: 10, y: 8)
        }
        .frame(width: MealTuning.bowlWidth, height: MealTuning.bowlHeight)
        .position(meal.bowlCenter)
        .allowsHitTesting(false)
    }

    /// The mound of food in the bowl, which pokes up over the rim once it is nearly full.
    private func heap(for pet: Pet, rimY: Double) -> some View {
        let fill = meal.bowlFill
        let width = (MealTuning.bowlWidth - 30) * (0.66 + 0.34 * fill)
        let height = 24 + 30 * fill
        let top = rimY + 4 - 8 * fill

        return ZStack {
            Ellipse()
                .fill(
                    LinearGradient(
                        colors: [pet.kind.foodColor.opacity(0.95),
                                 pet.kind.foodColor.opacity(0.6)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                )
                .frame(width: width, height: height)

            // A handful of individual pieces sitting proud of the heap.
            ForEach(Array(0..<Int((fill * 8).rounded())), id: \.self) { index in
                let spot = Self.heapScatter[index % Self.heapScatter.count]
                Capsule()
                    .fill(pet.kind.foodColor.opacity(0.9))
                    .frame(width: 11, height: 8)
                    .rotationEffect(.degrees(Double(index) * 37))
                    .offset(x: spot.x * (width / 160), y: spot.y - height / 2 + 6)
            }
        }
        .offset(y: top)
    }

    /// A fixed scatter, so the pile only grows and shrinks rather than reshuffling itself.
    private static let heapScatter: [CGPoint] = [
        CGPoint(x: -52, y: 6), CGPoint(x: -32, y: -2), CGPoint(x: -12, y: 3),
        CGPoint(x: 8, y: -4), CGPoint(x: 28, y: 2), CGPoint(x: 46, y: 8),
        CGPoint(x: -22, y: 11), CGPoint(x: 20, y: 10)
    ]

    // MARK: Food

    private func fallingFood(for pet: Pet) -> some View {
        ZStack {
            ForEach(meal.falling) { piece in
                kibble(piece, color: pet.kind.foodColor)
            }
            ForEach(meal.crumbs) { crumb in
                kibble(crumb, color: pet.kind.foodColor.opacity(0.8))
            }
        }
        .allowsHitTesting(false)
    }

    private func spilledFood(for pet: Pet) -> some View {
        ZStack {
            ForEach(meal.spilled) { piece in
                kibble(piece, color: pet.kind.foodColor.opacity(0.75))
            }
        }
        .allowsHitTesting(false)
    }

    private func kibble(_ piece: Kibble, color: Color) -> some View {
        Capsule()
            .fill(
                LinearGradient(colors: [color, color.opacity(0.65)],
                               startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .frame(width: piece.size, height: piece.size * 0.72)
            .rotationEffect(.degrees(piece.spin))
            .position(piece.position)
    }

    // MARK: Bag

    private func bagSprite(for pet: Pet) -> some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [Color(red: 0.87, green: 0.76, blue: 0.60),
                                 Color(red: 0.70, green: 0.57, blue: 0.41)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )
                .frame(width: 92, height: 116)

            // The rolled-open mouth of the bag, at the end food comes out of.
            Capsule()
                .fill(Color(red: 0.62, green: 0.49, blue: 0.35))
                .frame(width: 86, height: 20)
                .offset(y: -52)

            Image(systemName: pet.kind.symbolName)
                .font(.system(size: 30, weight: .bold))
                .foregroundStyle(pet.kind.foodColor.opacity(0.85))
                .offset(y: 8)
        }
        .rotationEffect(.degrees(meal.tipAngle))
        .shadow(color: .black.opacity(0.22), radius: 12, y: 8)
        .position(meal.bagPosition)
        .allowsHitTesting(false)
    }

    // MARK: Pet

    private func petSprite(for pet: Pet) -> some View {
        // Head down into the bowl with a bob on every mouthful — or a slow, pointed
        // head-shake at the food you have just put on the floor.
        let shake = sin(meal.sulkPhase * 5) * 7 * meal.annoyance

        return ZStack {
            PetFaceView(pet: pet, gaze: meal.gaze)
                .frame(width: 280, height: 300)
                .scaleEffect(MealTuning.petScale * (1 + 0.03 * meal.chew))
                .frame(width: 280 * MealTuning.petScale, height: 300 * MealTuning.petScale)
                .rotationEffect(.degrees(-24 * meal.headDip - 4 * meal.chew + shake))
                .offset(x: -22 * meal.headDip, y: 6 * meal.headDip + 5 * meal.chew)

            if meal.annoyance > 0.05 {
                Image(systemName: "exclamationmark.bubble.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(pet.palette.accent)
                    .opacity(min(meal.annoyance * 1.6, 1))
                    .offset(x: 46, y: -96)
            }
        }
        .position(meal.petPosition)
        .allowsHitTesting(false)
    }

    // MARK: Scoreboard

    private func scoreboard(for pet: Pet) -> some View {
        VStack(spacing: 10) {
            HStack(spacing: 14) {
                gauge("Bowl", value: meal.bowlFill,
                      tint: meal.isBowlFull ? .orange : pet.kind.foodColor)
                gauge("Bag", value: meal.bagFill, tint: .secondary)

                Button("Done") { meal.finish() }
                    .buttonStyle(.glass)
                    .controlSize(.small)
            }

            Text(hint(for: pet))
                .font(.footnote.weight(.medium))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: .infinity)
                .animation(.easeInOut(duration: 0.2), value: meal.isEating)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .glassEffect(in: .rect(cornerRadius: 22))
    }

    private func gauge(_ title: String, value: Double, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .font(.caption2.weight(.semibold))
                .foregroundStyle(.secondary)
            ProgressView(value: value)
                .progressViewStyle(.linear)
                .tint(tint)
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(title)
        .accessibilityValue("\(Int(value * 100)) percent")
    }

    private func hint(for pet: Pet) -> String {
        if meal.isSated {
            return "\(pet.name) has had plenty. Well done."
        }
        if meal.isSulking {
            return "\(pet.name) is glaring at the food on the floor."
        }
        if !meal.hasPoured {
            return "Press and hold the bag to tip it, and aim the food into the bowl."
        }
        if meal.isPouring {
            if meal.isBowlFull { return "That's plenty — lift your finger!" }
            return meal.annoyance > 0.05 ? "You're missing the bowl!" : "Keep it over the bowl."
        }
        if meal.isEating {
            return "\(pet.name) is tucking in."
        }
        if meal.bowlPieces > 0 {
            return meal.isTouching ? "Let go and \(pet.name) will come over."
                                   : "\(pet.name) is on the way."
        }
        if meal.bagRemaining == 0 {
            return "The bag is empty."
        }
        return "\(pet.name) would like some more."
    }
}

// MARK: - Shapes

/// The near half of a food bowl: a cup whose top edge is the front lip of the rim, so a
/// heap of food inside shows over the top of it.
struct BowlShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let rimHeight = rect.height * MealTuning.bowlRimRatio
        let left = CGPoint(x: rect.minX, y: rect.minY + rimHeight / 2)
        let right = CGPoint(x: rect.maxX, y: rect.minY + rimHeight / 2)

        path.move(to: left)
        // The front lip of the rim, curving towards the viewer.
        path.addQuadCurve(to: right,
                          control: CGPoint(x: rect.midX, y: rect.minY + rimHeight * 1.6))
        // Down the outside wall, across the base, and back up the other side.
        path.addCurve(
            to: CGPoint(x: rect.midX + rect.width * 0.17, y: rect.maxY),
            control1: CGPoint(x: rect.maxX - 4, y: rect.minY + rect.height * 0.6),
            control2: CGPoint(x: rect.midX + rect.width * 0.3, y: rect.maxY)
        )
        path.addLine(to: CGPoint(x: rect.midX - rect.width * 0.17, y: rect.maxY))
        path.addCurve(
            to: left,
            control1: CGPoint(x: rect.midX - rect.width * 0.3, y: rect.maxY),
            control2: CGPoint(x: rect.minX + 4, y: rect.minY + rect.height * 0.6)
        )
        path.closeSubpath()
        return path
    }
}
