import AuthenticationServices
import Foundation
import Security

/// The person a pet belongs to, as vouched for by Sign in with Apple.
///
/// There is no server behind any of this, so sign-in does exactly two jobs: it puts a
/// real Apple ID behind every pet, and it gets a name to call its owner by. The opaque
/// identifier Apple hands over is kept in the Keychain on this device and never leaves
/// it — nothing is uploaded, and no email address is even asked for.
@Observable
final class PetOwner {
    /// Everything the app knows about the person. The name arrives only at the very first
    /// authorization, so it is kept alongside the identifier rather than asked for again.
    struct Identity: Codable, Sendable, Equatable {
        /// Apple's opaque identifier for this person and this developer. Stable across
        /// reinstalls, which is what makes it worth storing.
        var userID: String
        /// Nil when the person declined to share a name, which they are entitled to do.
        var name: String?
    }

    enum Status: Equatable {
        case signedOut
        case signedIn(Identity)
    }

    /// Read straight from the Keychain at launch, so somebody who signed in last week
    /// never sees the gate flash up in front of them.
    private(set) var status: Status
    /// Set when an attempt failed for a reason worth putting on screen. Backing out of
    /// the sheet is not one of those reasons.
    private(set) var failure: String?

    /// Called whenever the gate opens or closes, so the rest of the app can stop and
    /// start the things a signed-out pet has no business doing.
    var onChange: (() -> Void)?

    private let provider = ASAuthorizationAppleIDProvider()
    private var revocationWatcher: Task<Void, Never>?

    init() {
        status = OwnerKeychain.load().map(Status.signedIn) ?? .signedOut

        // Apple asks that a credential withdrawn while the app is running signs the
        // person straight out, rather than leaving them in on a pass that no longer works.
        revocationWatcher = Task { [weak self] in
            let revocations = NotificationCenter.default.notifications(
                named: ASAuthorizationAppleIDProvider.credentialRevokedNotification
            )
            for await _ in revocations {
                guard let self else { return }
                self.signOut()
            }
        }
    }

    var identity: Identity? {
        guard case .signedIn(let identity) = status else { return nil }
        return identity
    }

    var isSignedIn: Bool { identity != nil }

    /// What to call the person, or nil if they kept their name to themselves.
    var displayName: String? { identity?.name }

    // MARK: Signing in

    /// The completion handler behind the Sign in with Apple button.
    func complete(_ result: Result<ASAuthorization, any Error>) {
        switch result {
        case .success(let authorization):
            guard let credential = authorization.credential as? ASAuthorizationAppleIDCredential else {
                failure = "That sign-in came back without an Apple ID."
                return
            }
            adopt(credential)

        case .failure(let error):
            failure = Self.message(for: error)
        }
    }

    private func adopt(_ credential: ASAuthorizationAppleIDCredential) {
        // The name is only ever sent the first time this app is authorized, so a name
        // already on file is carried forward rather than overwritten with the nothing a
        // later sign-in brings.
        let stored = OwnerKeychain.load()
        let carried = stored?.userID == credential.user ? stored?.name : nil
        let identity = Identity(
            userID: credential.user,
            name: credential.fullName.flatMap(Self.formatted) ?? carried
        )

        OwnerKeychain.save(identity)
        failure = nil
        status = .signedIn(identity)
        onChange?()
    }

    /// Forgets this device's copy of the identity. There is nothing to tell Apple about:
    /// the relationship with the Apple ID itself is managed in Settings, not in here.
    func signOut() {
        guard isSignedIn else { return }
        OwnerKeychain.erase()
        status = .signedOut
        failure = nil
        onChange?()
    }

    /// Asks the system whether the stored credential still stands. Worth doing at launch
    /// and on every return to the foreground, because access can be withdrawn from
    /// Settings while the app isn't running to hear about it.
    func refresh() async {
        guard let identity else { return }
        switch await credentialState(for: identity.userID) {
        case .authorized:
            break

        case .revoked:
            signOut()

        case .transferred:
            // The app has moved to a different developer team, so the identifier on file
            // is no longer one Apple will answer for. Signing in again mints the new one.
            signOut()

        case .notFound:
            // The Simulator reports this even for a credential it has just issued, which
            // would make the app impossible to sign into there.
            #if !targetEnvironment(simulator)
            signOut()
            #endif

        @unknown default:
            break
        }
    }

    private func credentialState(
        for userID: String
    ) async -> ASAuthorizationAppleIDProvider.CredentialState {
        await withCheckedContinuation { continuation in
            provider.getCredentialState(forUserID: userID) { state, _ in
                continuation.resume(returning: state)
            }
        }
    }

    // MARK: Text

    private nonisolated static func formatted(_ components: PersonNameComponents) -> String? {
        let name = components
            .formatted(.name(style: .medium))
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty ? nil : name
    }

    /// Nil for a cancellation: somebody who changed their mind does not need telling.
    private static func message(for error: any Error) -> String? {
        guard let error = error as? ASAuthorizationError else { return error.localizedDescription }
        switch error.code {
        case .canceled:
            return nil
        case .failed:
            return "Apple couldn't finish that sign-in. Try again in a moment."
        case .invalidResponse, .notHandled:
            return "Apple sent back something this app couldn't make sense of. Try again."
        case .notInteractive:
            return "Sign-in needs the screen. Unlock the phone and try again."
        default:
            return "Sign-in didn't work. Check you're signed in to iCloud in Settings, with two-factor authentication turned on."
        }
    }
}

/// The owner's identity on disk. This is the one piece of the app's state that is about
/// the person rather than the pet, so it goes in the Keychain rather than sitting in
/// `UserDefaults` next to the sound toggle.
private enum OwnerKeychain {
    private static let service = "us.gilman.VPet.owner"
    private static let account = "appleID"

    static func load() -> PetOwner.Identity? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return try? JSONDecoder().decode(PetOwner.Identity.self, from: data)
    }

    static func save(_ identity: PetOwner.Identity) {
        guard let data = try? JSONEncoder().encode(identity) else { return }
        // Written over the top of whatever was there: an update on a missing item fails,
        // and so does an add on an item that already exists.
        _ = SecItemDelete(baseQuery as CFDictionary)

        var item = baseQuery
        item[kSecValueData as String] = data
        // The pet's owner is only ever needed on the phone the pet lives on, and this
        // keeps the identifier out of iCloud Keychain and off every other device.
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        _ = SecItemAdd(item as CFDictionary, nil)
    }

    static func erase() {
        _ = SecItemDelete(baseQuery as CFDictionary)
    }

    private static var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
