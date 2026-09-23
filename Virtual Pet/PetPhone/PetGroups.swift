import Foundation

/// Friend groups: making them, getting into them with a code, and keeping every member's
/// copy of the roster in step.
///
/// Like everything else social in this app there is no server. A group is a log of
/// events that gets passed between phones in range and merged, and because the log only
/// grows, merging is a union and can never conflict. The practical consequence is that a
/// group only catches up when its members are actually near each other — which for a
/// friend group is most of the point.
///
/// One thing worth being straight about: none of this is signed. Any phone in range
/// could in principle make up an event claiming somebody promoted it. Everyone in a
/// group can already see everything in it, so this protects a roster rather than a
/// secret, and the honest summary is that it keeps friends organised rather than keeping
/// an attacker out.
@Observable
final class PetGroups {
    private(set) var groups: [PetGroup] = []
    /// Set when a join fails or a code turns out to be no good, for the join sheet.
    private(set) var statusMessage: String?
    /// True while a code is out looking for whoever has the group it belongs to.
    private(set) var isJoining = false

    /// Puts a message out over the nearby transport. Wired up by ``PetWorld``.
    var send: ((PetMessage, PetCard?) -> Void)?
    /// Who is in range at the moment. A roster is only ever sent to members, so this is
    /// what a group update gets aimed at.
    var nearby: () -> [PetCard] = { [] }
    /// Called once a join lands, so the pet can make a fuss about it.
    var onJoined: ((PetGroup) -> Void)?

    /// How long a code is left out looking before giving up. Somebody has to be in range
    /// with the group already on their phone, so this is a matter of seconds or never.
    private static let joinWindow: Duration = .seconds(8)

    /// Groups this phone has left. Kept so the next member to come along doesn't sync
    /// the group straight back on.
    @ObservationIgnored private var forgotten: Set<String> = []
    @ObservationIgnored private var pendingCode: String?
    @ObservationIgnored private var joinTask: Task<Void, Never>?

    // MARK: Lifecycle

    func load() {
        guard groups.isEmpty else { return }
        let stored = GroupArchive.load()
        groups = stored.groups
        forgotten = stored.forgotten
    }

    func erase() {
        groups = []
        forgotten = []
        statusMessage = nil
        cancelJoin()
        GroupArchive.erase()
    }

    // MARK: Lookups

    func group(id: String) -> PetGroup? {
        groups.first { $0.id == id }
    }

    /// The groups a pet is in, which for the feed means the ones worth showing a button
    /// for.
    func groups(containing petID: String) -> [PetGroup] {
        groups.filter { $0.contains(petID) }.sorted { $0.name < $1.name }
    }

    /// True when a postcard tagged with this group should be let in: the group has to be
    /// one of ours, and the sender has to actually be in it.
    func allowsPost(inGroup groupID: String, from authorID: String, myID: String) -> Bool {
        guard let group = group(id: groupID) else { return false }
        return group.contains(myID) && group.contains(authorID)
    }

    /// Everyone in range who is also in this group — the only phones a group postcard
    /// should ever be handed to.
    func recipients(inGroup groupID: String, among nearby: [PetCard]) -> [PetCard] {
        guard let group = group(id: groupID) else { return [] }
        return nearby.filter { group.contains($0.id) }
    }

    // MARK: Making and leaving

    @discardableResult
    func create(named name: String, as pet: Pet) -> PetGroup {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let group = PetGroup.founded(by: pet, named: trimmed.isEmpty ? "Our group" : trimmed)
        groups.append(group)
        persist()
        return group
    }

    /// Leaves a group, as far as this phone is concerned.
    ///
    /// Nothing is removed from anybody else's log — there is no mechanism for removing
    /// anything from a grow-only log, and inventing one would undo the permanence the
    /// roles depend on. So the other members go on listing you, and you stop seeing the
    /// group at all. The screen says as much before it happens.
    func forget(_ group: PetGroup) {
        groups.removeAll { $0.id == group.id }
        forgotten.insert(group.id)
        persist()
    }

    // MARK: Roles

    /// Co-host, for good. Anyone from co-host up can hand it out.
    func promoteToCoHost(_ member: GroupMemberInfo, in group: PetGroup, by pet: Pet) {
        let me = pet.id.uuidString
        guard let role = group.role(of: me), role.canPromoteToCoHost else { return }
        guard group.contains(member.id) else { return }
        guard group.role(of: member.id) == .member else { return }

        apply(
            GroupEvent(kind: .promoted, actorID: me, subjectID: member.id, subject: member),
            to: group
        )
    }

    /// Hands the host title over. The old host keeps co-host, because what they had
    /// can't be taken off them either — not even by themselves.
    func handHost(to member: GroupMemberInfo, in group: PetGroup, by pet: Pet) {
        let me = pet.id.uuidString
        guard group.role(of: me)?.canHandOverHost == true else { return }
        guard group.contains(member.id), member.id != me else { return }

        apply(
            GroupEvent(kind: .handedHost, actorID: me, subjectID: member.id, subject: member),
            to: group
        )
    }

    func regenerateCode(in group: PetGroup, by pet: Pet) {
        let me = pet.id.uuidString
        guard group.role(of: me)?.canChangeCode == true else { return }

        apply(
            GroupEvent(kind: .codeChanged, actorID: me, subjectID: me, text: InviteCode.make()),
            to: group
        )
    }

    // MARK: Joining

    /// Puts a code out to everyone in range. Whoever has the group answers with it.
    func beginJoin(code: String, as pet: Pet) {
        let normalised = InviteCode.normalised(code)
        guard InviteCode.isComplete(normalised) else {
            statusMessage = "That code isn't the right length."
            return
        }
        if let existing = groups.first(where: { $0.inviteCode == normalised }) {
            statusMessage = "You're already in \(existing.name)."
            return
        }

        cancelJoin()
        pendingCode = normalised
        isJoining = true
        statusMessage = nil
        send?(.groupProbe(normalised), nil)

        joinTask = Task { [weak self] in
            try? await Task.sleep(for: Self.joinWindow)
            guard let self, !Task.isCancelled, self.isJoining else { return }
            self.isJoining = false
            self.pendingCode = nil
            self.statusMessage = "Nobody nearby has that group. Ask whoever runs it to open Pet Phone next to you."
        }
    }

    func cancelJoin() {
        joinTask?.cancel()
        joinTask = nil
        isJoining = false
        pendingCode = nil
    }

    func clearStatus() {
        statusMessage = nil
    }

    /// Somebody nearby is holding up a code. Answer only if it opens one of our groups,
    /// and only if we are in that group ourselves.
    func handleProbe(code: String, from card: PetCard, myID: String) {
        let wanted = InviteCode.normalised(code)
        guard !wanted.isEmpty else { return }
        guard let group = groups.first(where: { $0.inviteCode == wanted && $0.contains(myID) })
        else { return }
        send?(.groupOffer(group), card)
    }

    /// The answer to our code came back. Write ourselves into the log and tell everyone.
    func handleOffer(_ offered: PetGroup, as pet: Pet) {
        guard let pendingCode, offered.inviteCode == pendingCode else { return }
        let me = pet.id.uuidString
        guard !offered.contains(me) else {
            // Already listed — an old membership catching up rather than a new join.
            cancelJoin()
            adopt(offered)
            return
        }

        cancelJoin()
        // Leaving and rejoining with a fresh code is a perfectly reasonable thing to do.
        forgotten.remove(offered.id)

        let joined = offered.appending(
            GroupEvent(kind: .joined, actorID: me, subjectID: me, subject: GroupMemberInfo(pet: pet))
        )
        adopt(joined)
        broadcast(joined)
        onJoined?(joined)
    }

    // MARK: Syncing

    /// A copy of a group has come in from somebody in range.
    func handleSync(_ incoming: PetGroup, myID: String) {
        guard !forgotten.contains(incoming.id) else { return }
        // Only groups we're already in. An unsolicited log for a group we've never heard
        // of is not an invitation — that's what the code is for.
        guard let mine = group(id: incoming.id), mine.contains(myID) else { return }

        let merged = mine.merging(incoming)
        guard merged != mine else { return }
        adopt(merged)
    }

    /// A phone has just turned up. Bring it up to date on every group it shares with us.
    func shareGroups(with card: PetCard, myID: String) {
        for group in groups where group.contains(myID) && group.contains(card.id) {
            send?(.groupSync(group), card)
        }
    }

    // MARK: Helpers

    /// Records an event locally and pushes the group out to everyone in range who is in
    /// it. Members who aren't nearby pick it up the next time they are.
    private func apply(_ event: GroupEvent, to group: PetGroup) {
        let updated = group.appending(event)
        adopt(updated)
        broadcast(updated)
    }

    /// Sends a roster to its members and to nobody else. Broadcasting it would tell
    /// every phone in the room who is in the group, which is not theirs to know.
    private func broadcast(_ group: PetGroup) {
        for card in nearby() where group.contains(card.id) {
            send?(.groupSync(group), card)
        }
    }

    private func adopt(_ group: PetGroup) {
        if let index = groups.firstIndex(where: { $0.id == group.id }) {
            groups[index] = group
        } else {
            groups.append(group)
        }
        persist()
    }

    private func persist() {
        GroupArchive.save(groups, forgotten: forgotten)
    }
}
