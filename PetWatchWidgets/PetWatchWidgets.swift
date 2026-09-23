import SwiftUI
import WidgetKit

/// One moment in the pet's day, read from the copy the watch app saved when the phone last
/// sent one over.
struct WatchPetEntry: TimelineEntry {
    let date: Date
    /// `nil` until a phone has sent a pet to this watch.
    let pet: Pet?

    /// Needs drift whether or not anyone is looking, so the complication runs the app's own
    /// simulation forward to the moment this entry will be shown.
    init(date: Date, pet: Pet?) {
        self.date = date
        self.pet = pet.map {
            var aged = $0
            aged.advance(to: date)
            return aged
        }
    }
}

/// Reads the same save file the watch app writes, in the watch's own App Group container.
/// The complication never talks to the phone itself — the app does that, and reloads these
/// timelines the moment a new pet lands.
struct WatchPetProvider: TimelineProvider {
    func placeholder(in context: Context) -> WatchPetEntry {
        WatchPetEntry(date: .now, pet: .watchSample)
    }

    func getSnapshot(in context: Context, completion: @escaping (WatchPetEntry) -> Void) {
        // In the gallery there may be no pet yet, and an empty complication sells nothing.
        let pet = context.isPreview ? .watchSample : PetArchive.load()
        completion(WatchPetEntry(date: .now, pet: pet))
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<WatchPetEntry>) -> Void) {
        let pet = PetArchive.load()
        let now = Date.now
        // Idle drift is slow and entirely predictable, so the next few hours can be drawn
        // up front. Anything the person actually does reloads this from the app.
        let entries = stride(from: 0, through: Self.lookAhead, by: Self.step).map {
            WatchPetEntry(date: now.addingTimeInterval($0), pet: pet)
        }
        completion(Timeline(entries: entries, policy: .atEnd))
    }

    private static let step: TimeInterval = 20 * 60
    private static let lookAhead: TimeInterval = 4 * 60 * 60
}

extension Pet {
    /// A stand-in pet for the complication gallery: a few days old, well loved, and just
    /// about ready for dinner.
    static var watchSample: Pet {
        var pet = Pet(name: "Mochi", kind: .cat)
        pet.bornAt = .now.addingTimeInterval(-6 * 86_400)
        pet.bondPoints = 220
        pet.needs = Needs(fullness: 0.46, fun: 0.72, affection: 0.88, rest: 0.64)
        return pet
    }
}

// MARK: - Complication

struct PetComplicationView: View {
    @Environment(\.widgetFamily) private var family
    let entry: WatchPetEntry

    var body: some View {
        content
            .containerBackground(.clear, for: .widget)
    }

    @ViewBuilder
    private var content: some View {
        switch family {
        case .accessoryCircular: circular
        case .accessoryCorner: corner
        default: wordy
        }
    }

    /// A ring of the neediest meter wrapped around the species glyph. On a watch face the
    /// ring is what gets read at a glance: a full ring means nothing needs doing.
    @ViewBuilder
    private var circular: some View {
        if let pet = entry.pet {
            if let need = pet.neediest {
                Gauge(value: pet.needs.value(for: need)) {
                    Image(systemName: need.symbolName)
                } currentValueLabel: {
                    Image(systemName: pet.kind.symbolName)
                }
                .gaugeStyle(.accessoryCircular)
                .tint(need.tint)
                .accessibilityLabel(pet.widgetSummary)
            } else {
                // Nothing wants anything, so the pet just looks pleased with itself.
                ZStack {
                    AccessoryWidgetBackground()
                    VStack(spacing: -2) {
                        Image(systemName: pet.kind.symbolName)
                            .font(.title3)
                        Text(pet.mood.emoji)
                            .font(.system(size: 10))
                    }
                }
                .accessibilityLabel(pet.widgetSummary)
            }
        } else {
            ZStack {
                AccessoryWidgetBackground()
                Image(systemName: "pawprint.fill")
            }
            .accessibilityLabel("No pet yet")
        }
    }

    /// The corner family gets the species glyph with a curved gauge along the bezel.
    @ViewBuilder
    private var corner: some View {
        if let pet = entry.pet {
            Image(systemName: pet.kind.symbolName)
                .font(.title2)
                .widgetLabel {
                    if let need = pet.neediest {
                        Gauge(value: pet.needs.value(for: need)) {
                            Text(need.label)
                        }
                        .tint(need.tint)
                    } else {
                        Text("\(pet.name) · \(pet.mood.label)")
                    }
                }
                .accessibilityLabel(pet.widgetSummary)
        } else {
            Image(systemName: "pawprint.fill")
                .font(.title2)
                .widgetLabel { Text("No pet") }
        }
    }

    /// Inline and rectangular get words, because that is what they have room for.
    @ViewBuilder
    private var wordy: some View {
        if let pet = entry.pet {
            ViewThatFits(in: .horizontal) {
                Label("\(pet.name) · \(pet.widgetHeadline)", systemImage: pet.kind.symbolName)
                Label(pet.widgetHeadline, systemImage: pet.kind.symbolName)
            }
            .accessibilityLabel(pet.widgetSummary)
        } else {
            Label("No pet yet", systemImage: "pawprint.fill")
        }
    }
}

struct PetComplication: Widget {
    let kind = "PetComplication"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: WatchPetProvider()) { entry in
            PetComplicationView(entry: entry)
        }
        .configurationDisplayName("Pet")
        .description("How your pet is doing, and what it wants.")
        .supportedFamilies([
            .accessoryCircular,
            .accessoryCorner,
            .accessoryInline,
            .accessoryRectangular
        ])
    }
}

#Preview(as: .accessoryCircular) {
    PetComplication()
} timeline: {
    WatchPetEntry(date: .now, pet: .watchSample)
}
