import SwiftUI

/// The pet, fitted into a watch-sized box.
///
/// `PetFaceView` draws a long way outside its own 280×300 layout frame — a cat's tail
/// swings right, a bunny's ears go well above the top — so the drawing is given a canvas
/// big enough for the whole animal, recentred inside it, and clipped as a backstop. Same
/// reasoning as the widget portrait, different numbers.
struct WatchPetPortrait: View {
    let pet: Pet
    /// Height of the box the pet is fitted into. Width follows the canvas' proportions.
    var height: Double = 96

    /// Room for every species' ears and tails, at the extremes of their animation.
    private static let canvas = CGSize(width: 400, height: 350)
    /// How far to shift the drawing to bring the whole animal into the middle.
    private static let recentre = CGSize(width: -34, height: 18)

    /// Only sizes above regular are reined in: a tiny pet should still look tiny, but a
    /// huge one would otherwise be cropped by a screen this small.
    private var size: Double { max(pet.appearance.size.scale, 1) }
    private var width: Double { height * Self.canvas.width / Self.canvas.height }

    var body: some View {
        PetFaceView(pet: pet)
            .offset(x: Self.recentre.width * size, y: Self.recentre.height * size)
            .frame(width: Self.canvas.width * size, height: Self.canvas.height * size)
            .scaleEffect(height / (Self.canvas.height * size))
            .frame(width: width, height: height)
            .clipped()
            .accessibilityHidden(true)
    }
}

/// One need as a bar. Chunkier than the widget's, because a wrist gets less attention than
/// a home screen does.
struct WatchNeedBar: View {
    let kind: NeedKind
    let value: Double

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: kind.symbolName)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(kind.tint)
                .frame(width: 14)
            Capsule()
                .fill(kind.tint.opacity(0.24))
                .frame(height: 8)
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

/// All four needs, the neediest at the top where the eye lands first.
struct WatchNeedStack: View {
    let needs: Needs

    private var ranked: [NeedKind] {
        NeedKind.allCases.sorted { needs.value(for: $0) < needs.value(for: $1) }
    }

    var body: some View {
        VStack(spacing: 7) {
            ForEach(ranked) { kind in
                WatchNeedBar(kind: kind, value: needs.value(for: kind))
            }
        }
    }
}

/// What the watch shows when there is no pet to show: either nobody has adopted one yet,
/// or this watch has never managed to speak to the phone.
struct WatchNoPetView: View {
    let hasPhone: Bool

    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: hasPhone ? "pawprint.fill" : "iphone.slash")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(hasPhone ? "No pet yet" : "No phone")
                .font(.headline)
            Text(hasPhone
                 ? "Adopt one on your iPhone and it'll turn up here."
                 : "Open Virtual Pet on your iPhone to send your pet over.")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .padding(.horizontal, 4)
        .accessibilityElement(children: .combine)
    }
}
