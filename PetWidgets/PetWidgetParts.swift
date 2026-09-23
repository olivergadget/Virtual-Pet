import SwiftUI
import WidgetKit

// `Pet.widgetHeadline`, `Pet.widgetSummary` and `NeedKind.tint` live in
// `Shared/PetSummary.swift`, because the watch complication needs the same words and the
// same colours as the widgets do.

/// The pet from the app's own screen, scaled to fit a widget.
///
/// `PetFaceView` draws well outside its own 280×300 layout frame: a cat's tail swings out
/// to x ≈ 230, a dog's to 195, and a bunny's ears reach y ≈ -186. On a full screen there is
/// room for that, but in a widget the overspill lands on whatever sits alongside — the need
/// bars and their symbols. So the portrait hands the pet a canvas big enough for the whole
/// animal, recentres the drawing inside it, and clips as a backstop.
struct PetPortrait: View {
    @Environment(\.widgetRenderingMode) private var renderingMode
    let pet: Pet
    /// Height of the box the pet is fitted into. Width follows the canvas' proportions.
    let height: Double

    /// Room for every species' ears and tails, at the extremes of their animation.
    private static let canvas = CGSize(width: 400, height: 350)
    /// Where the drawing sits in that canvas relative to the face, negated — the pet is
    /// shifted by this much to bring the whole animal into the middle.
    private static let recentre = CGSize(width: -34, height: 18)

    /// Only sizes above regular are normalised away: a tiny pet should still look tiny,
    /// but a huge one is reined in rather than cropped.
    private var size: Double { max(pet.appearance.size.scale, 1) }
    private var width: Double { height * Self.canvas.width / Self.canvas.height }

    var body: some View {
        Group {
            if renderingMode == .fullColor {
                PetFaceView(pet: pet)
                    .offset(x: Self.recentre.width * size, y: Self.recentre.height * size)
                    .frame(width: Self.canvas.width * size, height: Self.canvas.height * size)
                    .scaleEffect(height / (Self.canvas.height * size))
            } else {
                // Tinted and clear Home Screens flatten the widget to white and keep the
                // opacity of gradients, which leaves a pet built entirely from gradient
                // fills as a faint outline of itself. A solid glyph is what reads there.
                Image(systemName: pet.kind.symbolName)
                    .font(.system(size: height * 0.62))
                    .foregroundStyle(.primary)
            }
        }
        .frame(width: width, height: height)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// One need as a chunky bar. A widget is read at arm's length in half a second.
struct NeedBar: View {
    let kind: NeedKind
    let value: Double

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 9, weight: .bold))
                .foregroundStyle(kind.tint)
                .frame(width: 12)
            Capsule()
                .fill(kind.tint.opacity(0.22))
                .frame(height: 6)
                .overlay(alignment: .leading) {
                    GeometryReader { proxy in
                        Capsule()
                            .fill(kind.tint)
                            .frame(width: proxy.size.width * min(max(value, 0), 1))
                    }
                }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(kind.label)
        .accessibilityValue(value.formatted(.percent.precision(.fractionLength(0))))
    }
}

/// All four needs, stacked. The neediest one sits at the top where the eye lands.
struct NeedStack: View {
    let needs: Needs
    var spacing: Double = 5

    private var ranked: [NeedKind] {
        NeedKind.allCases.sorted { needs.value(for: $0) < needs.value(for: $1) }
    }

    var body: some View {
        VStack(spacing: spacing) {
            ForEach(ranked) { kind in
                NeedBar(kind: kind, value: needs.value(for: kind))
            }
        }
    }
}

/// Name, mood and what the pet is after, in one block.
struct PetCaption: View {
    let pet: Pet
    var isCompact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 1) {
            HStack(spacing: 4) {
                Text(pet.name)
                    .font(isCompact ? .subheadline.bold() : .headline)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text(pet.mood.emoji)
                    .font(isCompact ? .caption : .subheadline)
            }
            Text(pet.widgetHeadline)
                .font(isCompact ? .caption2 : .caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pet.widgetSummary)
    }
}

/// The pet's own sky, so the widget reads as a window onto the app.
struct PetSky: View {
    let pet: Pet?

    var body: some View {
        LinearGradient(
            colors: pet?.palette.sky ?? [.gray.opacity(0.22), .gray.opacity(0.38)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

/// What the widget shows before anybody has adopted anything.
struct NoPetView: View {
    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: "pawprint.fill")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("No pet yet")
                .font(.subheadline.bold())
            Text("Open Pet Phone to adopt one")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .accessibilityElement(children: .combine)
    }
}
