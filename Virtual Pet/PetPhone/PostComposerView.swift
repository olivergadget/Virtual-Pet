import SwiftUI
#if canImport(UIKit)
import UIKit

/// Making a postcard: point the camera at whatever you're doing, take the photo, then put
/// your pet on the front of it and send it to whoever is nearby.
///
/// Not everything worth saying has a photo to go with it, so the camera can be skipped
/// entirely — write a few words and the card's front becomes the words themselves, with
/// the pet standing on them exactly as it would stand on a photograph.
struct PostComposerView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    /// The group this postcard is for, taken from whichever feed it was started from.
    /// Nil means the open nearby feed.
    let groupID: String?
    let audienceName: String?

    @State private var camera = PostCamera()
    @State private var photo: UIImage?
    /// True when this is a written note rather than a photo, which is the one thing that
    /// decides what the whole screen is for.
    @State private var isWriting: Bool
    @State private var placement: StickerPlacement
    @State private var caption = ""

    init(groupID: String? = nil, audienceName: String? = nil, startsWriting: Bool = false) {
        self.groupID = groupID
        self.audienceName = audienceName
        _isWriting = State(initialValue: startsWriting)
        // A note stands the pet somewhere slightly different to a photo, and one opened
        // straight into writing never goes through ``startWriting()`` to be told so.
        _placement = State(initialValue: startsWriting ? .onNote : StickerPlacement())
    }

    /// What the card has on the front of it as things stand, or nil while there is still
    /// nothing to put on one.
    private var backdrop: PostcardBackdrop? {
        if let photo { return .photo(photo) }
        if isWriting { return .note(caption) }
        return nil
    }

    /// Captions sit under a photo, so they are kept short. A note is the card, so it gets
    /// more room.
    private var characterLimit: Int {
        isWriting ? PetPost.noteLimit : PetPost.captionLimit
    }

    private var words: String {
        caption.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Color.black.ignoresSafeArea()

                if let backdrop, let pet = world.pet {
                    editor(backdrop: backdrop, pet: pet)
                } else {
                    viewfinder
                }
            }
            .toolbarBackground(.hidden, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                if photo != nil {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Retake") { retake() }
                    }
                } else if isWriting {
                    ToolbarItem(placement: .primaryAction) {
                        Button("Camera") { startPhoto() }
                    }
                }
            }
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
        .preferredColorScheme(.dark)
        .task {
            // A composer opened straight into writing has no use for the camera, and
            // starting one is the most expensive thing on the screen.
            guard !isWriting else { return }
            await camera.start()
        }
        .onDisappear { camera.stop() }
        .onChange(of: camera.captured) { _, taken in
            guard let taken else { return }
            photo = taken
            camera.captured = nil
            // Nothing needs the camera while the sticker is being placed, and a running
            // session is the most expensive thing on the screen.
            camera.stop()
            PetHaptics.shared.tap(intensity: 0.75, sharpness: 0.95)
        }
    }

    // MARK: Viewfinder

    @ViewBuilder
    private var viewfinder: some View {
        switch camera.status {
        case .denied:
            notice(
                title: "No camera access",
                message: "Pet Phone needs the camera to photograph a postcard. You can turn it on in Settings — or write something instead.",
                symbolName: "camera.fill",
                actionTitle: "Open Settings",
                action: {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
            )

        case .failed(let reason):
            notice(
                title: "The camera didn't start",
                message: reason,
                symbolName: "exclamationmark.triangle.fill"
            )

        case .idle, .running:
            ZStack {
                CameraPreview(camera: camera)
                    .ignoresSafeArea()

                VStack {
                    Text(audienceName.map { "Show \($0) what you're up to." }
                         ?? "Show them what you're up to.")
                        .font(.footnote.weight(.medium))
                        .foregroundStyle(.white.opacity(0.85))
                        .padding(.horizontal, 14)
                        .padding(.vertical, 8)
                        .background(.black.opacity(0.35), in: Capsule())
                        .padding(.top, 8)

                    Spacer()
                    shutterBar
                }
                .padding(.bottom, 28)
            }
        }
    }

    private var shutterBar: some View {
        HStack {
            Spacer()

            Button {
                camera.capture()
            } label: {
                ZStack {
                    Circle()
                        .strokeBorder(.white, lineWidth: 4)
                        .frame(width: 76, height: 76)
                    Circle()
                        .fill(.white)
                        .frame(width: 62, height: 62)
                }
            }
            .buttonStyle(.plain)
            .disabled(camera.status != .running)
            .accessibilityLabel("Take photo")

            Spacer()
        }
        .overlay(alignment: .leading) {
            Button {
                startWriting()
            } label: {
                Image(systemName: "pencil.and.scribble")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.leading, 28)
            .accessibilityLabel("Write something instead")
        }
        .overlay(alignment: .trailing) {
            Button {
                camera.flip()
            } label: {
                Image(systemName: "arrow.triangle.2.circlepath.camera.fill")
                    .font(.title2)
                    .foregroundStyle(.white)
                    .padding(14)
                    .background(.black.opacity(0.35), in: Circle())
            }
            .buttonStyle(.plain)
            .padding(.trailing, 28)
            .accessibilityLabel("Switch camera")
        }
    }

    // MARK: Sticker and caption

    @ViewBuilder
    private func editor(backdrop: PostcardBackdrop, pet: Pet) -> some View {
        VStack(spacing: 16) {
            PostcardCanvas(
                backdrop: backdrop,
                pet: pet,
                placement: $placement,
                isEditable: true
            )
            .padding(.horizontal, 16)

            Text("Drag \(pet.name) about. Pinch to resize, twist to tilt, double-tap to turn them round.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            TextField(isWriting ? "Write something" : "Say something",
                      text: $caption,
                      axis: .vertical)
                .textFieldStyle(.plain)
                // A note is the whole card, so it is given more of the field to be
                // written in than a caption needs.
                .lineLimit(isWriting ? 1...5 : 1...3)
                .padding(12)
                .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
                .padding(.horizontal, 16)
                .onChange(of: caption) { _, updated in
                    if updated.count > characterLimit {
                        caption = String(updated.prefix(characterLimit))
                    }
                }

            if let message = world.postcards.statusMessage {
                Label(message, systemImage: "exclamationmark.triangle.fill")
                    .font(.footnote)
                    .foregroundStyle(.orange)
                    .padding(.horizontal, 16)
            }

            Button {
                send()
            } label: {
                Label(audienceName.map { "Send to \($0)" } ?? "Send it out",
                      systemImage: "paperplane.fill")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .padding(.horizontal, 16)
            // A note with nothing written on it is a blank card; a photo can go out
            // without a word on it.
            .disabled(isWriting && words.isEmpty)

            Text(audienceNote)
                .font(.caption2)
                .foregroundStyle(.white.opacity(0.55))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .padding(.vertical, 12)
    }

    /// Who this is actually going to, in plain terms, because "sharing" means something
    /// different for a group than it does for the open feed.
    private var audienceNote: String {
        guard world.preferences.postcardsEnabled else {
            return "Sharing is off in Settings, so this one stays on your phone."
        }
        if let groupID, let group = world.groups.group(id: groupID) {
            let count = group.members.count
            return "Only the \(count) \(count == 1 ? "pet" : "pets") in \(group.name) will ever see this. It reaches each of them the next time you're near each other."
        }
        return "Goes to Pet Phones nearby over the local network. Nothing is uploaded anywhere."
    }

    // MARK: Pieces

    @ViewBuilder
    private func notice(
        title: String,
        message: String,
        symbolName: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: symbolName)
        } description: {
            Text(message)
        } actions: {
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
            // Always offered: a postcard doesn't need the camera to be working.
            Button("Write something instead") { startWriting() }
        }
    }

    // MARK: Actions

    private func retake() {
        photo = nil
        isWriting = false
        placement = StickerPlacement()
        caption = ""
        Task { await camera.start() }
    }

    /// Puts the camera aside and turns the card over to the words.
    private func startWriting() {
        isWriting = true
        photo = nil
        placement = .onNote
        camera.stop()
    }

    /// Back to the camera from a note. Anything already written comes along as the
    /// photo's caption, trimmed to what a caption is allowed to be.
    private func startPhoto() {
        isWriting = false
        placement = StickerPlacement()
        if caption.count > PetPost.captionLimit {
            caption = String(caption.prefix(PetPost.captionLimit))
        }
        Task { await camera.start() }
    }

    private func send() {
        let sent = world.postPostcard(
            photo: photo,
            caption: caption,
            sticker: placement,
            groupID: groupID
        )
        guard sent != nil else { return }
        dismiss()
    }
}
#endif
