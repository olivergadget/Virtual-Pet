import SwiftUI

/// Everything the pet can do, everything it is halfway through learning, and everything
/// it is still too young to attempt. Tricks are taught from here, and asked for from here.
struct TrickBookView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss

    /// The lesson currently on screen, if any.
    @State private var lesson: TrickKind?

    var body: some View {
        NavigationStack {
            Group {
                if let pet = world.pet {
                    list(for: pet)
                } else {
                    ContentUnavailableView("No pet", systemImage: "pawprint")
                }
            }
            .navigationTitle("Tricks")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .fullScreenCover(item: $lesson) { trick in
            TrainingSessionView(trick: trick)
        }
    }

    private func list(for pet: Pet) -> some View {
        List {
            if pet.tricks.isEmpty {
                Section {
                    Text("\(pet.name) doesn't know anything yet. Pick a trick, say the word, and show \(pet.name) the hand signal — five goes at a time.")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            }

            let learned = pet.learnedTricks
            if !learned.isEmpty {
                Section("Knows") {
                    ForEach(learned) { record in
                        knownRow(record, pet: pet)
                    }
                }
            }

            let started = pet.teachableTricks.filter { !pet.knows($0) }
            if !started.isEmpty {
                Section(learned.isEmpty ? "Ready to learn" : "Still to learn") {
                    ForEach(started) { trick in
                        unlearnedRow(trick, pet: pet)
                    }
                }
            }

            let locked = pet.lockedTricks
            if !locked.isEmpty {
                Section("Not yet") {
                    ForEach(locked) { trick in
                        lockedRow(trick, pet: pet)
                    }
                }
            }
        }
    }

    // MARK: Rows

    private func knownRow(_ record: TrickRecord, pet: Pet) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Image(systemName: record.kind.symbolName)
                    .font(.body)
                    .foregroundStyle(pet.palette.accent)
                    .frame(width: 26)

                VStack(alignment: .leading, spacing: 1) {
                    Text(record.kind.displayName)
                        .font(.body.weight(.semibold))
                    Text("\(record.masteryTitle) · \(record.successes)/\(record.attempts) on cue")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Button("Ask") { ask(record.kind) }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)

                Button("Practise") { teach(record.kind) }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }

            ProgressView(value: record.mastery)
                .progressViewStyle(.linear)
                .tint(record.isReliable ? .green : pet.palette.accent)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(record.kind.displayName), \(record.masteryTitle)")
    }

    private func unlearnedRow(_ trick: TrickKind, pet: Pet) -> some View {
        let record = pet.record(for: trick)
        return HStack(spacing: 10) {
            Image(systemName: trick.symbolName)
                .font(.body)
                .foregroundStyle(.secondary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(trick.displayName)
                    .font(.body.weight(.semibold))
                Text(trick.signal.name)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)

            if let record, record.attempts > 0 {
                Text("\(record.attempts) tries")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Button("Teach") { teach(trick) }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.vertical, 2)
    }

    private func lockedRow(_ trick: TrickKind, pet: Pet) -> some View {
        HStack(spacing: 10) {
            Image(systemName: "lock.fill")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .frame(width: 26)

            VStack(alignment: .leading, spacing: 1) {
                Text(trick.displayName)
                    .font(.body.weight(.medium))
                Text("Needs level \(trick.requiredLevel) — \(pet.name) has to trust you further than this.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
        .foregroundStyle(.secondary)
    }

    // MARK: Actions

    /// Opens a lesson, unless the pet is too tired to sit through one.
    private func teach(_ trick: TrickKind) {
        guard world.canTrain else {
            world.declineTraining()
            dismiss()
            return
        }
        lesson = trick
    }

    /// Asks for a trick there and then. The performance happens on the home screen, so
    /// this gets out of the way first.
    private func ask(_ trick: TrickKind) {
        world.perform(trick)
        dismiss()
    }
}
