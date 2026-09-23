import SwiftUI
import WidgetKit

/// The home screen widget: the pet itself, looking however it currently feels.
struct PetStatusWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PetStatus", provider: PetProvider()) { entry in
            PetStatusView(entry: entry)
        }
        .configurationDisplayName("Your pet")
        .description("See how your pet is getting on without opening the app.")
        .supportedFamilies([.systemSmall, .systemMedium, .systemLarge])
    }
}

struct PetStatusView: View {
    @Environment(\.widgetFamily) private var family
    @Environment(\.widgetRenderingMode) private var renderingMode
    let entry: PetEntry

    var body: some View {
        content
            .containerBackground(for: .widget) {
                // Tinted and clear Home Screens come with their own glass or tint, and
                // the system strips the background anyway; the pet's sky would only be
                // flattened to a white haze over the top of it.
                if renderingMode == .fullColor {
                    PetSky(pet: entry.pet)
                } else {
                    Color.clear
                }
            }
    }

    @ViewBuilder
    private var content: some View {
        if let pet = entry.pet {
            switch family {
            case .systemMedium: medium(pet)
            case .systemLarge: large(pet)
            default: small(pet)
            }
        } else {
            NoPetView()
        }
    }

    // MARK: Sizes

    private func small(_ pet: Pet) -> some View {
        VStack(spacing: 2) {
            PetPortrait(pet: pet, height: 74)
            PetCaption(pet: pet, isCompact: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .overlay(alignment: .topTrailing) { celebration(pet) }
    }

    private func medium(_ pet: Pet) -> some View {
        HStack(spacing: 12) {
            PetPortrait(pet: pet, height: 104)
            VStack(alignment: .leading, spacing: 8) {
                PetCaption(pet: pet)
                NeedStack(needs: pet.needs)
            }
        }
        .overlay(alignment: .topTrailing) { celebration(pet) }
    }

    private func large(_ pet: Pet) -> some View {
        VStack(spacing: 10) {
            PetPortrait(pet: pet, height: 168)
            PetCaption(pet: pet)
                .frame(maxWidth: .infinity, alignment: .leading)
            NeedStack(needs: pet.needs, spacing: 7)
            HStack {
                Text("Level \(pet.level) · \(pet.levelTitle)")
                Spacer()
                Text(pet.ageDescription)
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .accessibilityElement(children: .combine)
        }
        .overlay(alignment: .topTrailing) { celebration(pet) }
    }

    /// A pet over the moon gets to show off about it, even here.
    @ViewBuilder
    private func celebration(_ pet: Pet) -> some View {
        if pet.mood == .ecstatic {
            Image(systemName: "sparkles")
                .font(.caption)
                .foregroundStyle(pet.palette.accent)
                .accessibilityHidden(true)
        }
    }
}

#Preview("Small", as: .systemSmall) {
    PetStatusWidget()
} timeline: {
    PetEntry(date: .now, pet: .sample)
    PetEntry(date: .now, pet: nil)
}

#Preview("Medium", as: .systemMedium) {
    PetStatusWidget()
} timeline: {
    PetEntry(date: .now, pet: .sample)
}

#Preview("Large", as: .systemLarge) {
    PetStatusWidget()
} timeline: {
    PetEntry(date: .now, pet: .sample)
}
