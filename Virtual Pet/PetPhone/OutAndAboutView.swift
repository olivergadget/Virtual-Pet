import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// Out & About. Postcards made on this phone and postcards handed over by other phones
/// that came within range, one to a screen, newest first.
///
/// Nothing here came off a server. A postcard from somebody else is in this feed because
/// their phone was close enough to pass it across — so the feed really is the local area,
/// rather than a list of strangers with a distance printed underneath.
///
/// The scope button switches between that open feed and one private feed per group,
/// which never mix: a group postcard is only ever sent to, and only ever accepted from,
/// somebody in that group.
struct OutAndAboutView: View {
    @Environment(PetWorld.self) private var world

    /// How the composer should open, and nil when it is shut. A postcard can start at
    /// the camera or at the keyboard, so the choice is made before it appears.
    private enum ComposerStart: Identifiable {
        case camera
        case writing

        var id: Self { self }
    }

    @State private var scope: FeedScope = .nearby
    @State private var composing: ComposerStart?

    private var myGroups: [PetGroup] {
        guard let myPetID = world.myPetID else { return [] }
        return world.groups.groups(containing: myPetID)
    }

    private var currentGroup: PetGroup? {
        scope.groupID.flatMap { world.groups.group(id: $0) }
    }

    private var title: String {
        currentGroup?.name ?? "Out & About"
    }

    private var visiblePosts: [PetPost] {
        world.postcards.posts(in: scope)
    }

    var body: some View {
        Group {
            #if canImport(UIKit)
            if visiblePosts.isEmpty {
                emptyFeed
            } else {
                feed
            }
            #else
            ContentUnavailableView {
                Label("Not available here", systemImage: "camera.fill")
            } description: {
                Text("Postcards need a camera.")
            }
            #endif
        }
        .navigationTitle(title)
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                scopeButton
            }
            #if canImport(UIKit)
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button("Take a photo", systemImage: "camera.fill") {
                        composing = .camera
                    }
                    Button("Write something", systemImage: "pencil.and.scribble") {
                        composing = .writing
                    }
                } label: {
                    Label("New postcard", systemImage: "plus")
                }
                .disabled(!world.hasPet)
            }
            #endif
        }
        #if canImport(UIKit)
        .fullScreenCover(item: $composing) { start in
            PostComposerView(
                groupID: scope.groupID,
                audienceName: currentGroup?.name,
                startsWriting: start == .writing
            )
        }
        #endif
        // A group left while its feed is open drops back to the open one.
        .onChange(of: world.groups.groups.count) { _, _ in
            if let groupID = scope.groupID, world.groups.group(id: groupID) == nil {
                scope = .nearby
            }
        }
    }

    /// Switches between the open feed and each group's. A plain menu rather than a row
    /// of chips, because most people will be in one or two groups and the title already
    /// says which feed you're looking at.
    private var scopeButton: some View {
        Menu {
            Picker("Feed", selection: $scope) {
                Label("Nearby", systemImage: "dot.radiowaves.left.and.right")
                    .tag(FeedScope.nearby)
                ForEach(myGroups) { group in
                    Label(group.name, systemImage: "person.2.fill")
                        .tag(FeedScope.group(group.id))
                }
            }
            .pickerStyle(.inline)

            Divider()

            NavigationLink {
                GroupsView()
            } label: {
                Label(myGroups.isEmpty ? "Start a group…" : "Manage groups…",
                      systemImage: "person.2.badge.gearshape")
            }
        } label: {
            Label(
                scope == .nearby ? "Nearby" : "Group",
                systemImage: scope == .nearby ? "dot.radiowaves.left.and.right" : "person.2.fill"
            )
        }
        .disabled(!world.hasPet)
    }

    #if canImport(UIKit)
    private var feed: some View {
        ScrollView {
            LazyVStack(spacing: 0) {
                ForEach(visiblePosts) { post in
                    PostcardPage(post: post)
                        // One postcard to a screenful, so a flick moves on by exactly one.
                        .containerRelativeFrame([.horizontal, .vertical])
                }
            }
        }
        .scrollTargetBehavior(.paging)
        .scrollIndicators(.hidden)
        .ignoresSafeArea(edges: .bottom)
    }

    private var emptyFeed: some View {
        ContentUnavailableView {
            Label(currentGroup == nil ? "Nothing doing" : "Nothing from \(currentGroup?.name ?? "")",
                  systemImage: "figure.walk.motion")
        } description: {
            Text(emptyMessage)
        } actions: {
            if world.hasPet {
                Button("Take a photo") { composing = .camera }
                    .buttonStyle(.borderedProminent)
                Button("Write something") { composing = .writing }
            }
        }
    }

    private var emptyMessage: String {
        guard world.hasPet else {
            return "Adopt a pet first — they have to be on the front of the postcard."
        }
        if let currentGroup {
            return "Nobody in \(currentGroup.name) has put anything up yet. Postcards you make here only go to its \(currentGroup.members.count) \(currentGroup.members.count == 1 ? "member" : "members")."
        }
        return "Take a photo of wherever you are and stick your pet on the front — or just write something, if there's nothing to photograph. Postcards from other Pet Phones nearby turn up here too."
    }
    #endif
}

#if canImport(UIKit)
/// One postcard, filling the screen: the photo with its sticker, then who sent it and
/// from how far away. Double-tap it to like it.
private struct PostcardPage: View {
    @Environment(PetWorld.self) private var world
    let post: PetPost

    @State private var isConfirmingRemoval = false
    /// Loaded in a task rather than read straight out of `body`, which keeps a JPEG
    /// decode out of the middle of a layout pass.
    @State private var image: UIImage?
    @State private var hasLooked = false
    /// The big heart that swells over a postcard the moment it is double-tapped.
    @State private var isShowingHeart = false

    private var isMine: Bool {
        world.postcards.isMine(post, pet: world.pet)
    }

    /// What goes on the front: the photo, or the words when there was never a photo to
    /// begin with. Nil while a photo is still being looked for.
    private var backdrop: PostcardBackdrop? {
        if post.isNote { return .note(post.caption) }
        return image.map { .photo($0) }
    }

    var body: some View {
        VStack(spacing: 14) {
            Spacer(minLength: 0)

            card
                .overlay { applause }
                .padding(.horizontal, 16)
                .contentShape(.rect)
                .onTapGesture(count: 2) { applaud() }

            // A note's words are already on the front of the card, so printing them
            // again underneath would just be saying it twice.
            if !post.caption.isEmpty, !post.isNote {
                Text(post.caption)
                    .font(.body)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 28)
            }

            byline

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .task(id: post.id) {
            image = world.postcards.image(for: post)
            hasLooked = true
        }
        // The heart is a passing thing, so it goes when the postcard is scrolled away
        // from rather than being found still hanging there on the way back.
        .onDisappear { isShowingHeart = false }
        .contentShape(.rect)
        .contextMenu {
            if isMine {
                Button("Take it down", systemImage: "trash", role: .destructive) {
                    isConfirmingRemoval = true
                }
            }
        }
        .confirmationDialog(
            "Take this postcard down?",
            isPresented: $isConfirmingRemoval,
            titleVisibility: .visible
        ) {
            Button("Take it down", role: .destructive) {
                world.postcards.remove(post)
            }
            Button("Keep it", role: .cancel) {}
        } message: {
            Text("It stays on any phone that already has a copy.")
        }
    }

    /// The front of the postcard, whatever it turned out to be.
    @ViewBuilder
    private var card: some View {
        if let backdrop {
            PostcardCanvas(
                backdrop: backdrop,
                pet: post.stickerPet,
                // The placement is fixed once a postcard is sent; nothing in the feed
                // can move the sticker about.
                placement: .constant(post.sticker)
            )
        } else {
            RoundedRectangle(cornerRadius: 26)
                .fill(.quaternary)
                .aspectRatio(3.0 / 4.0, contentMode: .fit)
                .overlay {
                    // Only say it's gone once looking for it has actually failed —
                    // a half-finished transfer, or a file that went missing behind
                    // the app's back. Before that it is simply still loading.
                    if hasLooked {
                        Label("Photo missing", systemImage: "photo")
                            .foregroundStyle(.secondary)
                    }
                }
        }
    }

    /// The heart that bursts over a postcard when it is double-tapped. It appears even
    /// when the postcard was already liked, because a gesture that does nothing at all
    /// feels like it went unheard.
    @ViewBuilder
    private var applause: some View {
        if isShowingHeart {
            Image(systemName: "heart.fill")
                .font(.system(size: 110))
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.35), radius: 14, y: 6)
                .transition(.scale(scale: 0.4).combined(with: .opacity))
                .allowsHitTesting(false)
        }
    }

    private var byline: some View {
        HStack(spacing: 10) {
            Image(systemName: post.kind.symbolName)
                .font(.footnote)
                .foregroundStyle(post.appearance.palette(for: post.kind).accent)

            VStack(alignment: .leading, spacing: 2) {
                Text(isMine ? "\(post.authorName) · you" : post.authorName)
                    .font(.subheadline.weight(.semibold))

                HStack(spacing: 6) {
                    Text(post.createdAt, style: .relative)
                    if let distance = world.postcards.distanceDescription(
                        of: post,
                        from: world.locator.coordinate
                    ) {
                        Text("·")
                        Text(distance)
                    }
                    Text("·")
                    Text("\(post.moodAtPosting.emoji) \(post.moodAtPosting.label)")
                }
                .font(.caption2)
                .foregroundStyle(.secondary)

                if let likedBy {
                    Text(likedBy)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }

            Spacer()

            likeControl
        }
        .padding(.horizontal, 28)
    }

    /// The heart. Somebody else's postcard can be liked and unliked; your own only ever
    /// shows the tally, because applauding yourself isn't a thing a pet would understand.
    @ViewBuilder
    private var likeControl: some View {
        let count = world.postcards.likeCount(for: post)

        if isMine {
            if count > 0 {
                heart(filled: true, count: count)
                    .foregroundStyle(.pink)
                    .accessibilityLabel(countLabel(count))
            }
        } else {
            let liked = world.postcards.hasLiked(post, pet: world.pet)
            Button {
                withAnimation(.snappy) {
                    _ = world.toggleLike(on: post)
                }
            } label: {
                heart(filled: liked, count: count)
            }
            .buttonStyle(.plain)
            .foregroundStyle(liked ? .pink : .secondary)
            .disabled(!world.hasPet)
            .accessibilityLabel(liked ? "Unlike" : "Like")
            .accessibilityValue(countLabel(count))
        }
    }

    private func heart(filled: Bool, count: Int) -> some View {
        HStack(spacing: 5) {
            Image(systemName: filled ? "heart.fill" : "heart")
                .contentTransition(.symbolEffect(.replace))
                .symbolEffect(.bounce, value: count)
            if count > 0 {
                Text(count, format: .number)
                    .contentTransition(.numericText())
            }
        }
        .font(.subheadline.weight(.medium))
        // Small symbols make for a small target, so the tap area is padded out to
        // something a thumb can actually find.
        .padding(.vertical, 6)
        .contentShape(.rect)
    }

    private func countLabel(_ count: Int) -> String {
        count == 1 ? "1 like" : "\(count) likes"
    }

    /// Double-tapping a postcard likes it.
    ///
    /// It never takes a like back: doing it twice is somebody saying the same thing
    /// again, not changing their mind, and a gesture that silently undid a like would
    /// be a nasty surprise. The heart in the byline is there for unliking.
    private func applaud() {
        // Applauding yourself isn't a thing a pet would understand, which is the same
        // reason your own postcards only ever show the tally.
        guard !isMine, world.hasPet else { return }

        if world.postcards.hasLiked(post, pet: world.pet) {
            // Already liked, so nothing changes — but the tap is still answered.
            PetHaptics.shared.tap(intensity: 0.35, sharpness: 0.4)
        } else {
            withAnimation(.snappy) {
                // Discarded inside the closure so `withAnimation` itself returns Void:
                // `@discardableResult` on `toggleLike` doesn't carry through it.
                _ = world.toggleLike(on: post)
            }
        }

        withAnimation(.spring(duration: 0.3, bounce: 0.55)) {
            isShowingHeart = true
        }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            withAnimation(.easeOut(duration: 0.3)) {
                isShowingHeart = false
            }
        }
    }

    /// Who liked it, named. With a feed this local it is nearly always somebody you have
    /// met, so the names are worth more than the number on its own.
    private var likedBy: String? {
        let names = world.postcards.likes(for: post).map { like in
            like.petID == world.myPetID ? "you" : like.petName
        }
        switch names.count {
        case 0: return nil
        case 1: return "Liked by \(names[0])"
        case 2: return "Liked by \(names[0]) and \(names[1])"
        default: return "Liked by \(names[0]), \(names[1]) and \(names.count - 2) more"
        }
    }
}
#endif

#Preview {
    NavigationStack {
        OutAndAboutView()
    }
    .environment(PetWorld.shared)
}
