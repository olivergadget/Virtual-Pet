import AuthenticationServices
import SwiftUI

/// The gate in front of the whole app. A pet belongs to somebody, and this is where that
/// somebody is established — nothing else happens until it is. See ``PetOwner`` for what
/// is kept afterwards, which is an opaque identifier and a name, on this device only.
struct SignInView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.colorScheme) private var colorScheme

    /// The pet's own colours once there is a pet to take them from, so a returning owner
    /// is met by their own animal's sky rather than a stranger's.
    private var palette: PetPalette {
        world.pet?.palette ?? PetKind.cat.palette
    }

    private var returningPet: Pet? { world.pet }

    var body: some View {
        ZStack {
            LinearGradient(colors: palette.sky, startPoint: .topLeading, endPoint: .bottomTrailing)
                .ignoresSafeArea()

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 24) {
                        headline
                        assurances
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 40)
                    .padding(.bottom, 12)
                }
                .scrollBounceBehavior(.basedOnSize)

                footer
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)
            }
        }
    }

    // MARK: Pieces

    private var headline: some View {
        VStack(spacing: 16) {
            if let pet = returningPet {
                PetFaceView(pet: pet)
                    .scaleEffect(0.7)
                    .frame(height: 220)
                    .accessibilityLabel("\(pet.name) is waiting")
            } else {
                Image(systemName: "pawprint.fill")
                    .font(.system(size: 62))
                    .foregroundStyle(palette.accent)
                    .padding(.vertical, 24)
            }

            VStack(spacing: 8) {
                Text(returningPet.map { "\($0.name) is waiting" } ?? "Every pet needs a person")
                    .font(.largeTitle.weight(.bold))
                    .multilineTextAlignment(.center)
                Text(returningPet == nil
                     ? "Sign in with Apple and the pet you adopt is yours — one owner, one animal, no username to forget."
                     : "Sign in with Apple to let them know it's you.")
                    .font(.subheadline)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var assurances: some View {
        VStack(spacing: 12) {
            assurance(
                symbol: "lock.fill",
                title: "Stays on this phone",
                detail: "There is no server to sign in to. Apple's identifier for you is kept in this phone's Keychain and goes nowhere else."
            )
            assurance(
                symbol: "envelope.badge.shield.half.filled",
                title: "No email address asked for",
                detail: "Only your name, and only so your pet has somebody to belong to. Withhold it and the pet copes."
            )
        }
    }

    private func assurance(symbol: String, title: String, detail: String) -> some View {
        HStack(alignment: .top, spacing: 14) {
            Image(systemName: symbol)
                .font(.title3)
                .foregroundStyle(palette.accent)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glassEffect(in: .rect(cornerRadius: 20))
    }

    private var footer: some View {
        VStack(spacing: 12) {
            if let failure = world.owner.failure {
                Text(failure)
                    .font(.caption)
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.red)
                    .transition(.opacity)
            }

            SignInWithAppleButton(returningPet == nil ? .signUp : .signIn) { request in
                // Only the name: an email address would be of no use to an app with
                // nothing to send one from.
                request.requestedScopes = [.fullName]
            } onCompletion: { result in
                world.owner.complete(result)
            }
            .signInWithAppleButtonStyle(colorScheme == .dark ? .white : .black)
            .frame(height: 50)
            // The one control on the screen, so it gets the full width of it.
            .frame(maxWidth: .infinity)
        }
        .animation(.easeInOut(duration: 0.25), value: world.owner.failure)
    }
}

#Preview {
    SignInView()
        .environment(PetWorld.shared)
}
