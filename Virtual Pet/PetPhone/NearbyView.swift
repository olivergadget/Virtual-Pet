import SwiftUI

/// Playdates. Two phones running Pet Phone in the same room find each other over
/// peer-to-peer Wi-Fi and their pets introduce themselves without anybody signing in.
struct NearbyView: View {
    @Environment(PetWorld.self) private var world

    var body: some View {
        List {
            if let message = world.social.statusMessage {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.footnote)
                        .foregroundStyle(.orange)
                }
            }

            Section {
                if world.social.nearby.isEmpty {
                    ContentUnavailableView {
                        Label("No pets nearby", systemImage: "dot.radiowaves.left.and.right")
                    } description: {
                        Text(world.preferences.nearbyEnabled
                             ? "Open Pet Phone on another device in the same room and the two pets will find each other."
                             : "Playdates are switched off in Settings.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(world.social.nearby) { card in
                        NearbyPetRow(card: card)
                    }
                }
            } header: {
                Text("In the room")
            } footer: {
                if world.social.isRunning {
                    Text("Discovery runs only while Pet Phone is open, and no pet data leaves the local network.")
                }
            }

            if let friends = world.pet?.friends, !friends.isEmpty {
                Section("Friends made") {
                    ForEach(friends) { friend in
                        FriendRow(friend: friend)
                    }
                }
            }

            if !world.social.log.isEmpty {
                Section("Recently") {
                    ForEach(world.social.log) { entry in
                        HStack(spacing: 12) {
                            Image(systemName: entry.symbolName)
                                .foregroundStyle(.tint)
                                .frame(width: 24)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.text)
                                    .font(.subheadline)
                                Text(entry.date, style: .relative)
                                    .font(.caption2)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Playdates")
    }
}

private struct NearbyPetRow: View {
    @Environment(PetWorld.self) private var world
    let card: PetCard

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: card.kind.symbolName)
                    .font(.title2)
                    .foregroundStyle(card.kind.palette.accent)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 2) {
                    Text(card.name)
                        .font(.headline)
                    Text(card.headline)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            HStack(spacing: 10) {
                Button {
                    world.nuzzle(card)
                } label: {
                    Label("Nuzzle", systemImage: "heart.fill")
                }
                Button {
                    world.sendTreat(to: card)
                } label: {
                    Label("Treat", systemImage: "gift.fill")
                }
                Button {
                    world.invitePlay(card)
                } label: {
                    Label("Play", systemImage: "tennisball.fill")
                }
            }
            .font(.caption.weight(.semibold))
            .buttonStyle(.bordered)
            .controlSize(.small)
        }
        .padding(.vertical, 4)
    }
}

private struct FriendRow: View {
    let friend: FriendRecord

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: friend.kind.symbolName)
                .foregroundStyle(friend.kind.palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(friend.name)
                    .font(.subheadline.weight(.semibold))
                Text("\(friend.bondTitle) · met \(friend.meetings) \(friend.meetings == 1 ? "time" : "times")")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                ProgressView(value: friend.bond)
                    .progressViewStyle(.linear)
                    .tint(friend.kind.palette.accent)
            }
        }
        .padding(.vertical, 2)
    }
}
