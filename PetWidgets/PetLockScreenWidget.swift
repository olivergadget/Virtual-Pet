#if os(iOS)
import SwiftUI
import WidgetKit

/// The Lock Screen widgets. No room for the pet's face here, so these answer the one
/// question worth asking at a glance: does anybody need you?
struct PetLockScreenWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "PetNeeds", provider: PetProvider()) { entry in
            PetLockScreenView(entry: entry)
                .containerBackground(for: .widget) { Color.clear }
        }
        .configurationDisplayName("Pet needs")
        .description("Keep an eye on your pet from the Lock Screen.")
        .supportedFamilies([.accessoryCircular, .accessoryRectangular, .accessoryInline])
    }
}

struct PetLockScreenView: View {
    @Environment(\.widgetFamily) private var family
    let entry: PetEntry

    var body: some View {
        switch family {
        case .accessoryInline: inline
        case .accessoryRectangular: rectangular
        default: circular
        }
    }

    // MARK: Families

    @ViewBuilder
    private var inline: some View {
        if let pet = entry.pet {
            Label("\(pet.name) · \(pet.widgetHeadline)", systemImage: pet.kind.symbolName)
        } else {
            Label("No pet yet", systemImage: "pawprint.fill")
        }
    }

    @ViewBuilder
    private var rectangular: some View {
        if let pet = entry.pet {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Image(systemName: pet.kind.symbolName)
                        .font(.caption2)
                    Text(pet.name)
                        .font(.headline)
                        .lineLimit(1)
                }
                .widgetAccentable()

                Text(pet.widgetHeadline)
                    .font(.caption)
                    .lineLimit(1)

                // Monochrome up here, so the needs are told apart by their symbols
                // and how full they are rather than by colour.
                HStack(spacing: 5) {
                    ForEach(NeedKind.allCases) { kind in
                        HStack(spacing: 2) {
                            Image(systemName: kind.symbolName)
                                .font(.system(size: 8, weight: .bold))
                            Text(pet.needs.value(for: kind).formatted(.percent.precision(.fractionLength(0))))
                                .font(.system(size: 9, weight: .medium))
                        }
                        .opacity(pet.needs.value(for: kind) < 0.55 ? 1 : 0.55)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(pet.widgetSummary)
        } else {
            Label("Open Pet Phone to adopt a pet", systemImage: "pawprint.fill")
                .font(.caption)
        }
    }

    @ViewBuilder
    private var circular: some View {
        if let pet = entry.pet {
            Gauge(value: pet.moodScore) {
                Image(systemName: pet.neediest?.symbolName ?? pet.kind.symbolName)
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel(pet.widgetSummary)
        } else {
            Gauge(value: 0) {
                Image(systemName: "pawprint.fill")
            }
            .gaugeStyle(.accessoryCircularCapacity)
            .accessibilityLabel("No pet yet")
        }
    }
}

#Preview("Circular", as: .accessoryCircular) {
    PetLockScreenWidget()
} timeline: {
    PetEntry(date: .now, pet: .sample)
}

#Preview("Rectangular", as: .accessoryRectangular) {
    PetLockScreenWidget()
} timeline: {
    PetEntry(date: .now, pet: .sample)
    PetEntry(date: .now, pet: nil)
}

#Preview("Inline", as: .accessoryInline) {
    PetLockScreenWidget()
} timeline: {
    PetEntry(date: .now, pet: .sample)
}
#endif
