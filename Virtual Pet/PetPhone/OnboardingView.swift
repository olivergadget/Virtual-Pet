import SwiftUI

/// Adoption flow: pick a species, name it, grant the two permissions the pet needs to
/// reach you, then it moves in.
struct OnboardingView: View {
    private enum Step: Int, CaseIterable {
        case species
        case name
        case permissions
    }

    @Environment(PetWorld.self) private var world

    @State private var step: Step = .species
    @State private var kind: PetKind = .cat
    @State private var name = ""

    private var previewPet: Pet {
        Pet(name: resolvedName, kind: kind)
    }

    private var resolvedName: String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? kind.suggestedNames[0] : trimmed
    }

    var body: some View {
        ZStack {
            LinearGradient(colors: kind.palette.sky, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()
                .animation(.easeInOut(duration: 0.5), value: kind)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        switch step {
                        case .species: speciesStep
                        case .name: nameStep
                        case .permissions: permissionsStep
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 24)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
        .animation(.spring(duration: 0.4), value: step)
    }

    // MARK: Steps

    private var speciesStep: some View {
        VStack(spacing: 20) {
            VStack(spacing: 8) {
                Text("Your phone needs a pet")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text("It will live in here. It will want holding, feeding and playing with — and it will let you know when it doesn't get any.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            LazyVGrid(columns: [GridItem(spacing: 12), GridItem(spacing: 12)], spacing: 12) {
                ForEach(PetKind.allCases) { candidate in
                    Button {
                        kind = candidate
                        PetVoice.shared.play(candidate.voice.delighted, voice: candidate.voice, volume: 0.8)
                        PetHaptics.shared.tap(intensity: 0.5, sharpness: 0.3)
                    } label: {
                        VStack(spacing: 10) {
                            Image(systemName: candidate.symbolName)
                                .font(.system(size: 34))
                                .foregroundStyle(candidate.palette.accent)
                            Text(candidate.displayName)
                                .font(.headline)
                            Text(candidate.tagline)
                                .font(.caption2)
                                .multilineTextAlignment(.center)
                                .foregroundStyle(.secondary)
                                .frame(height: 46, alignment: .top)
                        }
                        .padding(14)
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.plain)
                    .glassEffect(
                        kind == candidate ? .regular.tint(candidate.palette.accent.opacity(0.4)) : .regular,
                        in: .rect(cornerRadius: 20)
                    )
                    .overlay {
                        RoundedRectangle(cornerRadius: 20)
                            .stroke(candidate.palette.accent, lineWidth: kind == candidate ? 3 : 0)
                    }
                    .accessibilityLabel(candidate.displayName)
                    .accessibilityHint(candidate.tagline)
                    .accessibilityAddTraits(kind == candidate ? [.isSelected, .isButton] : .isButton)
                }
            }

            Text("Tap one to hear it.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var nameStep: some View {
        VStack(spacing: 20) {
            PetFaceView(pet: previewPet)
                .scaleEffect(0.78)
                .frame(height: 250)

            Text("What's their name?")
                .font(.title2.weight(.bold))

            TextField(kind.suggestedNames[0], text: $name)
                .font(.title3)
                .multilineTextAlignment(.center)
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled()
                .submitLabel(.done)
                .padding(.vertical, 14)
                .padding(.horizontal, 18)
                .glassEffect(in: .rect(cornerRadius: 18))

            HStack(spacing: 8) {
                ForEach(kind.suggestedNames, id: \.self) { suggestion in
                    Button(suggestion) { name = suggestion }
                        .font(.caption.weight(.semibold))
                        .buttonStyle(.bordered)
                        .controlSize(.small)
                }
            }
        }
    }

    private var permissionsStep: some View {
        VStack(spacing: 18) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 54))
                .foregroundStyle(kind.palette.accent)

            Text("Two things \(resolvedName) needs")
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            VStack(spacing: 12) {
                permissionCard(
                    symbol: "bell.badge.fill",
                    title: "Notifications",
                    detail: "So \(resolvedName) can call for you when the app is closed. This is the whole point of a pet that lives in your phone.",
                    granted: world.notifier.isAuthorized,
                    action: { Task { await world.notifier.requestAuthorization() } }
                )
                permissionCard(
                    symbol: "location.fill",
                    title: "Location",
                    detail: "So \(resolvedName) learns where home is and notices when you're out. It stays on this device.",
                    granted: world.locator.isAuthorized,
                    action: { world.locator.requestAccess() }
                )
            }

            Text("Both are optional, but a pet that can't reach you is a lonely one.")
                .font(.caption)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
        }
        .task(id: step) {
            // Ask for both up front, the way the pet actually needs them.
            guard step == .permissions else { return }
            if world.notifier.authorization == .notDetermined {
                await world.notifier.requestAuthorization()
            }
            if world.locator.authorization == .notDetermined {
                world.locator.requestAccess()
            }
        }
    }

    private func permissionCard(
        symbol: String,
        title: String,
        detail: String,
        granted: Bool,
        action: @escaping () -> Void
    ) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(granted ? .green : kind.palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
            if granted {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: action)
                    .font(.caption.weight(.semibold))
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    // MARK: Footer

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 6) {
                ForEach(Step.allCases, id: \.rawValue) { candidate in
                    Capsule()
                        .fill(candidate == step ? kind.palette.accent : Color.primary.opacity(0.18))
                        .frame(width: candidate == step ? 22 : 8, height: 8)
                }
            }

            HStack(spacing: 12) {
                if step != .species {
                    Button("Back") {
                        step = Step(rawValue: step.rawValue - 1) ?? .species
                    }
                    .buttonStyle(.glass)
                    .controlSize(.large)
                }

                Button {
                    advance()
                } label: {
                    Text(step == .permissions ? "Adopt \(resolvedName)" : "Continue")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.glassProminent)
                .controlSize(.large)
            }
        }
    }

    private func advance() {
        switch step {
        case .species:
            step = .name
        case .name:
            step = .permissions
        case .permissions:
            world.adopt(name: resolvedName, kind: kind)
        }
    }
}
