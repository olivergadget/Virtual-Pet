import SwiftUI

/// The pet designer: species, size and colours, with a live preview of the result.
/// Shared between adoption — where the species is picked on its own step — and settings.
struct PetDesignView: View {
    @Binding var kind: PetKind
    @Binding var appearance: PetAppearance
    /// Name to describe the preview with, for VoiceOver.
    var previewName: String
    /// Onboarding chooses the species on an earlier step, so it hides the row here.
    var showsSpecies = true

    @Environment(\.self) private var environment

    private var scheme: PetColorScheme { appearance.colors(for: kind) }

    private var previewPet: Pet {
        Pet(name: previewName, kind: kind, appearance: appearance)
    }

    var body: some View {
        VStack(spacing: 18) {
            preview
            if showsSpecies { speciesSection }
            sizeSection
            colorSection
            if appearance.isCustomised { resetButton }
        }
    }

    // MARK: Preview

    private var preview: some View {
        ZStack {
            LinearGradient(colors: scheme.sky.map(\.color), startPoint: .top, endPoint: .bottom)
            PetFaceView(pet: previewPet)
                .scaleEffect(0.56)
        }
        .frame(height: 240)
        .clipShape(.rect(cornerRadius: 26))
        .animation(.easeInOut(duration: 0.35), value: scheme)
        .accessibilityElement()
        .accessibilityLabel(
            "Preview of \(previewName), a \(appearance.size.displayName.lowercased()) \(kind.displayName.lowercased())"
        )
    }

    // MARK: Species

    private var speciesSection: some View {
        section("Type") {
            HStack(spacing: 10) {
                ForEach(PetKind.allCases) { candidate in
                    Button {
                        kind = candidate
                        PetVoice.shared.play(candidate.voice.delighted, voice: candidate.voice, volume: 0.75)
                        PetHaptics.shared.tap(intensity: 0.5, sharpness: 0.3)
                    } label: {
                        VStack(spacing: 6) {
                            Image(systemName: candidate.symbolName)
                                .font(.title2)
                            Text(candidate.displayName)
                                .font(.caption.weight(.semibold))
                                .lineLimit(1)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(kind == candidate ? scheme.accent.color : .primary)
                    .background {
                        RoundedRectangle(cornerRadius: 16)
                            .fill(scheme.accent.color.opacity(kind == candidate ? 0.18 : 0.06))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16)
                                    .stroke(scheme.accent.color, lineWidth: kind == candidate ? 2.5 : 0)
                            }
                    }
                    .accessibilityLabel(candidate.displayName)
                    .accessibilityHint(candidate.tagline)
                    .accessibilityAddTraits(kind == candidate ? [.isSelected, .isButton] : .isButton)
                }
            }
        }
    }

    // MARK: Size

    private var sizeSection: some View {
        section("Size") {
            VStack(alignment: .leading, spacing: 8) {
                Picker("Size", selection: $appearance.size) {
                    ForEach(PetSize.allCases) { size in
                        Text(size.displayName).tag(size)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .onChange(of: appearance.size) { _, _ in
                    PetHaptics.shared.tap(intensity: 0.45, sharpness: 0.5)
                }

                Text(appearance.size.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Colours

    private var colorSection: some View {
        section("Colours") {
            VStack(alignment: .leading, spacing: 18) {
                colorRow(title: "Coat", keyPath: \.coat,
                         swatches: PetSwatches.coat, fallback: kind.colors.coat)
                colorRow(title: "Belly", keyPath: \.belly,
                         swatches: PetSwatches.belly, fallback: kind.colors.belly)
                colorRow(title: "Accent", keyPath: \.accent,
                         swatches: PetSwatches.accent, fallback: kind.colors.accent)
            }
        }
    }

    private func colorRow(
        title: String,
        keyPath: WritableKeyPath<PetAppearance, PetColor?>,
        swatches: [PetSwatch],
        fallback: PetColor
    ) -> some View {
        let current = appearance[keyPath: keyPath] ?? fallback

        return VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Spacer(minLength: 0)
                ColorPicker(
                    "Custom \(title.lowercased()) colour",
                    selection: colorBinding(for: keyPath, fallback: fallback),
                    supportsOpacity: false
                )
                .labelsHidden()
            }

            ScrollView(.horizontal) {
                HStack(spacing: 12) {
                    ForEach(swatches) { swatch in
                        let isSelected = swatch.color == current
                        Button {
                            appearance[keyPath: keyPath] = swatch.color
                            PetHaptics.shared.tap(intensity: 0.4, sharpness: 0.6)
                        } label: {
                            Circle()
                                .fill(swatch.color.color)
                                .frame(width: 38, height: 38)
                                .overlay {
                                    Circle().stroke(.primary.opacity(0.12), lineWidth: 1)
                                }
                                .overlay {
                                    Circle()
                                        .stroke(.primary, lineWidth: isSelected ? 2.5 : 0)
                                        .padding(-4)
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(swatch.name)
                        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
                    }
                }
                // Room for the selection ring, which sits outside the swatch itself.
                .padding(5)
            }
            .scrollIndicators(.hidden)
        }
    }

    /// Bridges the stored components to the system colour picker, which deals in `Color`.
    private func colorBinding(
        for keyPath: WritableKeyPath<PetAppearance, PetColor?>,
        fallback: PetColor
    ) -> Binding<Color> {
        Binding(
            get: { (appearance[keyPath: keyPath] ?? fallback).color },
            set: { appearance[keyPath: keyPath] = PetColor($0, in: environment) }
        )
    }

    // MARK: Reset

    private var resetButton: some View {
        Button("Back to a stock \(kind.displayName.lowercased())", systemImage: "arrow.uturn.backward") {
            appearance = PetAppearance()
            PetHaptics.shared.tap(intensity: 0.5, sharpness: 0.4)
        }
        .font(.footnote.weight(.semibold))
        .buttonStyle(.bordered)
        .controlSize(.small)
    }

    // MARK: Layout

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 22))
    }
}

/// The designer as a screen of its own, driven straight off the live pet so every change
/// shows up on the home screen the moment it's made.
struct PetDesignScreen: View {
    @Environment(PetWorld.self) private var world

    var body: some View {
        ScrollView {
            if let pet = world.pet {
                PetDesignView(
                    kind: Binding(get: { pet.kind }, set: { world.changeKind(to: $0) }),
                    appearance: Binding(get: { pet.appearance }, set: { world.updateAppearance($0) }),
                    previewName: pet.name
                )
                .padding(.horizontal, 20)
                .padding(.vertical, 16)
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .background {
            if let pet = world.pet {
                LinearGradient(colors: pet.palette.sky, startPoint: .top, endPoint: .bottom)
                    .ignoresSafeArea()
            }
        }
        .navigationTitle("Design")
    }
}

#Preview {
    @Previewable @State var kind: PetKind = .cat
    @Previewable @State var appearance = PetAppearance()

    ScrollView {
        PetDesignView(kind: $kind, appearance: $appearance, previewName: "Mochi")
            .padding(20)
    }
    .background {
        LinearGradient(colors: appearance.palette(for: kind).sky,
                       startPoint: .top, endPoint: .bottom)
            .ignoresSafeArea()
    }
}
