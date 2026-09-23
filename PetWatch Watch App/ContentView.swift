import SwiftUI

/// The whole watch app: the pet, how it is doing, and the two things worth doing about it
/// from a wrist. Tricks live one tap away, because asking for a trick is a thing you go
/// and do rather than something you need in your eyeline.
struct PetWatchHomeView: View {
    @Environment(PetWatchStore.self) private var store

    var body: some View {
        NavigationStack {
            ScrollView {
                if let pet = store.pet {
                    content(for: pet)
                } else {
                    WatchNoPetView(hasPhone: store.hasPhone)
                        .padding(.top, 20)
                }
            }
            .navigationTitle(store.pet?.name ?? "Virtual Pet")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    @ViewBuilder
    private func content(for pet: Pet) -> some View {
        VStack(spacing: 10) {
            ZStack(alignment: .bottom) {
                WatchPetPortrait(pet: pet)
                // The phone's speech bubble, cut down to a strip the watch has room for.
                if let note = store.note {
                    Text(note)
                        .font(.caption2)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 3)
                        .background(.black.opacity(0.55), in: .capsule)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: store.note)

            headline(for: pet)
            WatchNeedStack(needs: pet.needs)
            careButtons(for: pet)

            if !pet.learnedTricks.isEmpty {
                NavigationLink {
                    WatchTrickListView()
                } label: {
                    Label("Tricks", systemImage: "pawprint.fill")
                }
                .buttonStyle(.bordered)
            }

            footer
        }
        .padding(.horizontal, 6)
        .padding(.bottom, 8)
    }

    private func headline(for pet: Pet) -> some View {
        VStack(spacing: 1) {
            Text("\(pet.mood.emoji) \(pet.widgetHeadline)")
                .font(.footnote.weight(.semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("Level \(pet.level) · \(pet.levelTitle)")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(pet.widgetSummary)
    }

    private func careButtons(for pet: Pet) -> some View {
        HStack(spacing: 6) {
            Button {
                store.feed()
            } label: {
                Label("Feed", systemImage: "fork.knife")
                    .frame(maxWidth: .infinity)
            }
            .disabled(!store.canFeed)

            Button {
                store.cuddle()
            } label: {
                Label("Cuddle", systemImage: "heart.fill")
                    .frame(maxWidth: .infinity)
            }
        }
        .buttonStyle(.bordered)
        .labelStyle(.iconOnly)
        .font(.title3)
    }

    /// Only says anything when there is something the person can act on. A working sync is
    /// silent, because "connected" is not news.
    @ViewBuilder
    private var footer: some View {
        if !store.hasPhone {
            Label("No phone paired", systemImage: "iphone.slash")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if store.isWaitingOnPhone {
            Label("Telling your iPhone…", systemImage: "arrow.triangle.2.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
        } else if !store.isPhoneReachable {
            Label("Will sync when your iPhone is near", systemImage: "clock.arrow.circlepath")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
    }
}

#Preview {
    PetWatchHomeView()
        .environment(PetWatchStore.shared)
}
