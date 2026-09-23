import SwiftUI
#if canImport(UIKit)
import UIKit
#endif

/// One group: the code to get in, who's in it, and what you're allowed to do about that.
struct GroupDetailView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.dismiss) private var dismiss

    /// Held by id rather than by value, so the screen follows the group as members join
    /// and roles change underneath it.
    let groupID: String

    @State private var promotionTarget: GroupMemberInfo?
    @State private var handoverTarget: GroupMemberInfo?
    @State private var isConfirmingLeave = false
    @State private var hasCopiedCode = false

    private var group: PetGroup? { world.groups.group(id: groupID) }

    private var myRole: GroupRole? {
        guard let group, let myPetID = world.myPetID else { return nil }
        return group.role(of: myPetID)
    }

    var body: some View {
        Group {
            if let group, let myRole {
                content(group: group, myRole: myRole)
            } else {
                // Only reachable by leaving the group while standing on this screen.
                ContentUnavailableView(
                    "Not in this group",
                    systemImage: "person.2.slash",
                    description: Text("You've left, so there's nothing here to show.")
                )
            }
        }
        .navigationTitle(group?.name ?? "Group")
        .inlineNavigationTitle()
    }

    @ViewBuilder
    private func content(group: PetGroup, myRole: GroupRole) -> some View {
        List {
            inviteSection(group: group, myRole: myRole)

            Section {
                ForEach(group.rankedMembers) { member in
                    MemberRow(
                        member: member,
                        role: group.role(of: member.id) ?? .member,
                        isMe: member.id == world.myPetID
                    )
                    .contentShape(.rect)
                    .contextMenu {
                        memberActions(for: member, group: group, myRole: myRole)
                    }
                }
            } header: {
                Text("Members")
            } footer: {
                if myRole > .member {
                    Text("Touch and hold somebody to make them a co-host\(myRole == .host ? ", or to hand them the group" : ""). Neither can be undone — not by you, and not by them.")
                } else {
                    Text("Only the host and co-hosts can change who's who.")
                }
            }

            Section {
                Button("Leave group…", role: .destructive) {
                    isConfirmingLeave = true
                }
            } footer: {
                Text("Leaving takes the group and its postcards off this phone. The others go on listing you, because nothing can be removed from a group's history — that's what makes the permissions permanent.")
            }
        }
        .confirmationDialog(
            "Leave \(group.name)?",
            isPresented: $isConfirmingLeave,
            titleVisibility: .visible
        ) {
            Button("Leave", role: .destructive) {
                world.leaveGroup(group)
                dismiss()
            }
            Button("Stay", role: .cancel) {}
        } message: {
            Text(myRole == .host
                 ? "You're the host. Hand it to somebody else first, or the group is left without one."
                 : "Its postcards go too.")
        }
        .confirmationDialog(
            "Make \(promotionTarget?.name ?? "them") a co-host?",
            isPresented: Binding(get: { promotionTarget != nil }, set: { if !$0 { promotionTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Make co-host") {
                guard let member = promotionTarget, let pet = world.pet else { return }
                world.groups.promoteToCoHost(member, in: group, by: pet)
                promotionTarget = nil
            }
            Button("Cancel", role: .cancel) { promotionTarget = nil }
        } message: {
            Text("They'll be able to invite people and promote others. This can't be undone by anybody, including you.")
        }
        .confirmationDialog(
            "Hand \(group.name) to \(handoverTarget?.name ?? "them")?",
            isPresented: Binding(get: { handoverTarget != nil }, set: { if !$0 { handoverTarget = nil } }),
            titleVisibility: .visible
        ) {
            Button("Hand over the group", role: .destructive) {
                guard let member = handoverTarget, let pet = world.pet else { return }
                world.groups.handHost(to: member, in: group, by: pet)
                handoverTarget = nil
            }
            Button("Cancel", role: .cancel) { handoverTarget = nil }
        } message: {
            Text("They become the host and you drop to co-host. You won't be able to take it back — only they can hand it on again.")
        }
    }

    // MARK: Invite code

    @ViewBuilder
    private func inviteSection(group: PetGroup, myRole: GroupRole) -> some View {
        Section {
            HStack {
                Text(group.inviteCode)
                    .font(.system(.title, design: .monospaced, weight: .bold))
                    .kerning(4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .accessibilityLabel("Invite code, \(group.inviteCode.map(String.init).joined(separator: " "))")

                #if canImport(UIKit)
                Button {
                    UIPasteboard.general.string = group.inviteCode
                    hasCopiedCode = true
                    PetHaptics.shared.tap(intensity: 0.4, sharpness: 0.8)
                } label: {
                    Label(hasCopiedCode ? "Copied" : "Copy",
                          systemImage: hasCopiedCode ? "checkmark" : "doc.on.doc")
                        .labelStyle(.titleAndIcon)
                        .font(.footnote.weight(.semibold))
                }
                .buttonStyle(.bordered)
                #endif
            }

            if myRole.canChangeCode {
                Button("New code") {
                    guard let pet = world.pet else { return }
                    world.groups.regenerateCode(in: group, by: pet)
                    hasCopiedCode = false
                }
            }
        } header: {
            Text("Invite code")
        } footer: {
            Text(myRole.canChangeCode
                 ? "Read this out to somebody standing next to you. A new code stops the old one working, but nobody already in is affected."
                 : "Anyone with this code can join while a member is nearby.")
        }
        .onChange(of: group.inviteCode) { _, _ in hasCopiedCode = false }
    }

    // MARK: Member actions

    @ViewBuilder
    private func memberActions(
        for member: GroupMemberInfo,
        group: PetGroup,
        myRole: GroupRole
    ) -> some View {
        let theirRole = group.role(of: member.id) ?? .member
        let isMe = member.id == world.myPetID

        if myRole.canPromoteToCoHost, theirRole == .member, !isMe {
            Button("Make co-host", systemImage: GroupRole.coHost.symbolName) {
                promotionTarget = member
            }
        }
        if myRole.canHandOverHost, !isMe {
            Button("Make host", systemImage: GroupRole.host.symbolName) {
                handoverTarget = member
            }
        }
    }
}

private struct MemberRow: View {
    let member: GroupMemberInfo
    let role: GroupRole
    let isMe: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: member.kind.symbolName)
                .font(.title3)
                .foregroundStyle(member.appearance.palette(for: member.kind).accent)
                .frame(width: 30)

            Text(isMe ? "\(member.name) · you" : member.name)
                .font(.subheadline.weight(.medium))

            Spacer()

            if role > .member {
                Label(role.label, systemImage: role.symbolName)
                    .labelStyle(.titleAndIcon)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(role == .host ? .orange : .secondary)
            }
        }
        .padding(.vertical, 2)
    }
}
