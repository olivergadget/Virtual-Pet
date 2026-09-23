import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// A pet drawn small enough to stick on a photo.
///
/// ``PetFaceView`` lays itself out at a fixed size and animates from a `TimelineView`, so
/// a sticker is that same view scaled down rather than a flat copy of it. That is what
/// keeps the creature on a postcard breathing and blinking instead of sitting there like
/// a photograph — including on a phone that has never met the pet in question.
struct PetSticker: View {
    let pet: Pet
    /// How wide the sticker should be drawn.
    let width: Double
    var isFlipped = false

    /// The size ``PetFaceView`` draws itself at.
    private static let naturalSize = CGSize(width: 280, height: 300)

    var body: some View {
        let scale = width / Self.naturalSize.width

        PetFaceView(pet: pet)
            .frame(width: Self.naturalSize.width, height: Self.naturalSize.height)
            .scaleEffect(scale)
            .frame(width: width, height: Self.naturalSize.height * scale)
            // A sticker needs to sit off the photo rather than in it, and a soft drop
            // shadow is what does that.
            .shadow(color: .black.opacity(0.4), radius: 12 * scale, y: 6 * scale)
            .scaleEffect(x: isFlipped ? -1 : 1)
    }
}

#if canImport(UIKit)
/// What is on the front of a postcard, behind the pet.
enum PostcardBackdrop {
    case photo(UIImage)
    /// Something typed rather than photographed, where the words themselves are the
    /// front of the card.
    case note(String)
}

/// A postcard front with a pet stuck on it — drawn the same way in the composer and in
/// the feed so that what you place is exactly what people see.
///
/// The container takes the photo's own aspect ratio, which means the sticker's unit
/// coordinates land in the same place at any size. A written note has no photo to take a
/// shape from, so it gets one of its own.
struct PostcardCanvas: View {
    let backdrop: PostcardBackdrop
    let pet: Pet
    @Binding var placement: StickerPlacement
    /// True in the composer, where the sticker can be dragged, pinched, twisted and
    /// double-tapped. False everywhere else.
    var isEditable = false

    /// The sticker's natural width, as a fraction of the photo's. Scale is a multiplier
    /// on top of this.
    private static let stickerWidthFraction = 0.42
    /// The shape a written note takes: a little taller than it is wide, which is room
    /// for a few lines without the card running off the screen.
    private static let noteAspectRatio = 4.0 / 5.0

    /// Anchors taken when each gesture begins, so a drag moves the sticker from where it
    /// was rather than from wherever the finger landed.
    @State private var dragAnchor: CGPoint?
    @State private var scaleAnchor: Double?
    @State private var rotationAnchor: Double?

    private var aspectRatio: Double {
        switch backdrop {
        case .photo(let image):
            guard image.size.height > 0 else { return 1 }
            return image.size.width / image.size.height
        case .note:
            return Self.noteAspectRatio
        }
    }

    var body: some View {
        GeometryReader { proxy in
            let size = proxy.size
            ZStack {
                front(in: size)
                sticker(in: size)
            }
        }
        .aspectRatio(aspectRatio, contentMode: .fit)
        .clipShape(RoundedRectangle(cornerRadius: 26))
    }

    @ViewBuilder
    private func front(in size: CGSize) -> some View {
        switch backdrop {
        case .photo(let image):
            Image(uiImage: image)
                .resizable()
                .scaledToFill()
                .frame(width: size.width, height: size.height)
                .clipped()

        case .note(let text):
            NoteFront(text: text, pet: pet, size: size)
        }
    }

    @ViewBuilder
    private func sticker(in size: CGSize) -> some View {
        let width = size.width * Self.stickerWidthFraction * placement.scale

        PetSticker(pet: pet, width: width, isFlipped: placement.isFlipped)
            .rotationEffect(.degrees(placement.rotation))
            .position(x: placement.x * size.width, y: placement.y * size.height)
            .modify(when: isEditable) { view in
                view
                    .gesture(drag(in: size))
                    .simultaneousGesture(magnify)
                    .simultaneousGesture(twist)
                    .onTapGesture(count: 2) {
                        placement.isFlipped.toggle()
                        PetHaptics.shared.tap(intensity: 0.4, sharpness: 0.8)
                    }
            }
            // Only the composer wants to be prodded; in the feed the sticker is part of
            // the picture and shouldn't swallow a scroll.
            .allowsHitTesting(isEditable)
    }

    // MARK: Gestures

    private func drag(in size: CGSize) -> some Gesture {
        DragGesture()
            .onChanged { value in
                guard size.width > 0, size.height > 0 else { return }
                let anchor = dragAnchor ?? CGPoint(x: placement.x, y: placement.y)
                dragAnchor = anchor
                placement.x = anchor.x + value.translation.width / size.width
                placement.y = anchor.y + value.translation.height / size.height
                placement.clamp()
            }
            .onEnded { _ in dragAnchor = nil }
    }

    private var magnify: some Gesture {
        MagnifyGesture()
            .onChanged { value in
                let anchor = scaleAnchor ?? placement.scale
                scaleAnchor = anchor
                placement.scale = anchor * value.magnification
                placement.clamp()
            }
            .onEnded { _ in scaleAnchor = nil }
    }

    private var twist: some Gesture {
        RotateGesture()
            .onChanged { value in
                let anchor = rotationAnchor ?? placement.rotation
                rotationAnchor = anchor
                placement.rotation = anchor + value.rotation.degrees
            }
            .onEnded { _ in rotationAnchor = nil }
    }
}

/// The front of a written note: the author's pet's own sky with their words on it.
///
/// The colours come from the pet rather than from the app, so somebody's notes all look
/// like they came from that creature instead of out of a text box.
private struct NoteFront: View {
    let text: String
    let pet: Pet
    /// How big the card is being drawn, which everything here is sized from — a note
    /// laid out in points would come out as a different card in a thumbnail than it does
    /// full screen, and the whole point of the canvas is that it doesn't.
    let size: CGSize

    /// The sky is pale on most species and nearly black on a dragon, so it is taken down
    /// to a depth the writing reads against whichever pet sent it.
    private static let deepening = 0.5
    /// How much of the card the writing may take up. The rest is where the pet stands,
    /// so a long note shrinks to fit rather than running over the top of it.
    private static let writingHeightFraction = 0.55

    var body: some View {
        let scheme = pet.appearance.colors(for: pet.kind)
        let sky = scheme.sky.map { $0.darkened(by: Self.deepening).color }

        LinearGradient(colors: sky, startPoint: .top, endPoint: .bottom)
            .frame(width: size.width, height: size.height)
            .overlay(alignment: .top) {
                Text(text)
                    .font(.system(size: max(size.width * 0.075, 11),
                                  weight: .semibold,
                                  design: .rounded))
                    .foregroundStyle(.white)
                    .shadow(color: .black.opacity(0.3),
                            radius: size.width * 0.012,
                            y: size.width * 0.004)
                    .multilineTextAlignment(.center)
                    .minimumScaleFactor(0.55)
                    .frame(maxWidth: .infinity,
                           maxHeight: size.height * Self.writingHeightFraction,
                           alignment: .top)
                    .padding(.horizontal, size.width * 0.1)
                    .padding(.top, size.width * 0.14)
            }
    }
}
#endif

extension View {
    /// Applies a set of modifiers only under a condition, which keeps the gesture pile in
    /// ``PostcardCanvas`` out of the read-only version of the same view.
    @ViewBuilder
    func modify<Modified: View>(
        when condition: Bool,
        transform: (Self) -> Modified
    ) -> some View {
        if condition {
            transform(self)
        } else {
            self
        }
    }
}
