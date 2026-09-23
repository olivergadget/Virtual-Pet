import SwiftUI

/// The tricks the pet can already do, ready to be asked for from the wrist.
///
/// Only learned tricks appear. Teaching is a two-handed job involving hand signals drawn
/// on glass, so it stays on the phone — the watch is for showing off what the pet already
/// knows.
struct WatchTrickListView: View {
    @Environment(PetWatchStore.self) private var store
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            if let pet = store.pet, !pet.learnedTricks.isEmpty {
                ForEach(pet.learnedTricks) { record in
                    Button {
                        store.perform(record.kind)
                        // The answer comes back on the home screen, where the pet is.
                        dismiss()
                    } label: {
                        row(for: record)
                    }
                }
            } else {
                Text("Nothing learned yet. Teach a trick on your iPhone.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("Tricks")
    }

    private func row(for record: TrickRecord) -> some View {
        HStack(spacing: 9) {
            Image(systemName: record.kind.symbolName)
                .font(.footnote)
                .foregroundStyle(record.isReliable ? .green : .orange)
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 0) {
                Text(record.kind.displayName)
                    .font(.footnote.weight(.medium))
                    .lineLimit(1)
                Text(record.masteryTitle)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityHint("Asks your pet to perform this trick")
    }
}
