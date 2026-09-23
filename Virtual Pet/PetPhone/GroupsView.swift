import SwiftUI

extension View {
    /// `navigationBarTitleDisplayMode` doesn't exist on macOS, which this project still
    /// lists among its supported platforms.
    @ViewBuilder
    func inlineNavigationTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }
}

/// The list of friend groups: what you're in, and the two ways to get into another one.
struct GroupsView: View {
    @Environment(PetWorld.self) private var world

    @State private var isCreating = false
    @State private var isJoining = false

    private var myGroups: [PetGroup] {
        guard let myPetID = world.myPetID else { return [] }
        return world.groups.groups(containing: myPetID)
    }

    var body: some View {
        List {
            Section {
                if myGroups.isEmpty {
                    ContentUnavailableView {
                        Label("No groups yet", systemImage: "person.2.fill")
                    } description: {
                        Text("A group is a private feed for one set of friends. Start one and hand out the code, or type in somebody else's.")
                    }
                    .listRowBackground(Color.clear)
                } else {
                    ForEach(myGroups) { group in
                        NavigationLink {
                            GroupDetailView(groupID: group.id)
                        } label: {
                            GroupRow(group: group, myPetID: world.myPetID)
                        }
                    }
                }
            } header: {
                Text("Your groups")
            }

            Section {
                Button {
                    isCreating = true
                } label: {
                    Label("Start a group", systemImage: "plus.circle.fill")
                }
                Button {
                    world.groups.clearStatus()
                    isJoining = true
                } label: {
                    Label("Join with a code", systemImage: "number")
                }
            } footer: {
                Text("Groups live on the phones in them. Joining, and everything after it, needs the two of you to be near each other with Pet Phone open.")
            }
        }
        .navigationTitle("Groups")
        .disabled(!world.hasPet)
        .sheet(isPresented: $isCreating) {
            CreateGroupSheet()
        }
        .sheet(isPresented: $isJoining) {
            JoinGroupSheet()
        }
    }
}

private struct GroupRow: View {
    let group: PetGroup
    let myPetID: String?

    private var myRole: GroupRole? {
        myPetID.flatMap { group.role(of: $0) }
    }

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "person.2.fill")
                .foregroundStyle(.tint)
                .frame(width: 28)

            VStack(alignment: .leading, spacing: 3) {
                Text(group.name)
                    .font(.headline)

                HStack(spacing: 6) {
                    Text("\(group.members.count) \(group.members.count == 1 ? "pet" : "pets")")
                    if let myRole, myRole > .member {
                        Text("·")
                        Label(myRole.label, systemImage: myRole.symbolName)
                            .labelStyle(.titleAndIcon)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Starting one

private struct CreateGroupSheet: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Group name", text: $name)
                        .submitLabel(.done)
                        .onSubmit(create)
                } footer: {
                    Text("You'll be the host. You can make anyone else a co-host, or hand the whole thing over — neither can be taken back afterwards.")
                }
            }
            .navigationTitle("Start a group")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Start", action: create)
                        .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func create() {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        _ = world.createGroup(named: name)
        dismiss()
    }
}

// MARK: - Joining one

private struct JoinGroupSheet: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss

    @State private var code = ""

    private var isReady: Bool { InviteCode.isComplete(code) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("ABC234", text: $code)
                        .font(.system(.title2, design: .monospaced, weight: .semibold))
                        .multilineTextAlignment(.center)
                        // No need to ask the keyboard for capitals: `onChange` below
                        // normalises every keystroke to the code alphabet anyway.
                        .autocorrectionDisabled()
                        .submitLabel(.join)
                        .onSubmit(join)
                        .onChange(of: code) { _, typed in
                            let tidied = InviteCode.normalised(typed)
                            if tidied != typed { code = tidied }
                        }
                } footer: {
                    Text("Six characters from whoever runs the group. They need to be nearby with Pet Phone open — the group is on their phone, not on a server.")
                }

                if world.groups.isJoining {
                    Section {
                        HStack(spacing: 10) {
                            ProgressView()
                            Text("Looking for the group…")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                if let message = world.groups.statusMessage {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle.fill")
                            .font(.footnote)
                            .foregroundStyle(.orange)
                    }
                }
            }
            .navigationTitle("Join a group")
            .inlineNavigationTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        world.groups.cancelJoin()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Join", action: join)
                        .disabled(!isReady || world.groups.isJoining)
                }
            }
            // The sheet closes itself the moment the group actually lands.
            .onChange(of: world.groups.groups.count) { _, _ in
                if !world.groups.isJoining, world.groups.statusMessage == nil {
                    dismiss()
                }
            }
        }
    }

    private func join() {
        guard isReady else { return }
        world.joinGroup(code: code)
    }
}
