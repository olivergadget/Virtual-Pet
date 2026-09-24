import SwiftUI

/// Root router: sign-in until there's an owner, adoption until there's a pet, then the
/// four tabs.
struct ContentView: View {
    @Environment(PetWorld.self) private var world

    var body: some View {
        Group {
            if !world.owner.isSignedIn {
                SignInView()
            } else if world.hasPet {
                TabView {
                    Tab("Pet", systemImage: "heart.fill") {
                        PetHomeView()
                    }
                    Tab("Out & About", systemImage: "figure.walk.motion") {
                        NavigationStack {
                            OutAndAboutView()
                        }
                    }
                    Tab("Playdates", systemImage: "dot.radiowaves.left.and.right") {
                        NavigationStack {
                            NearbyView()
                        }
                    }
                    Tab("Settings", systemImage: "gearshape.fill") {
                        NavigationStack {
                            PetSettingsView()
                        }
                    }
                }
            } else {
                OnboardingView()
            }
        }
        // Presented from the root rather than the pet screen, so a friend turning up
        // takes over whichever tab is open.
        .fullScreenCover(item: reunion) { cast in
            ReunionView(cast: cast)
        }
        .task {
            // Asked first: access withdrawn in Settings while the app was closed should
            // put the gate back up rather than let somebody through on a dead credential.
            await world.owner.refresh()
            await world.start()
        }
        // Re-run when the gate opens, so a returning owner who had to sign in again is
        // still asked for anything the pet is missing.
        .task(id: world.owner.isSignedIn) {
            await requestStartupPermissions()
        }
    }

    /// The reunion waiting to be shown, if nothing else has the screen.
    private var reunion: Binding<ReunionCast?> {
        Binding {
            world.isBusyWithSession ? nil : world.reunion
        } set: { newValue in
            if newValue == nil { world.cancelReunion() }
        }
    }

    /// Returning players get both prompts at launch; new ones get them during adoption.
    /// Neither is asked for behind the sign-in gate, where there is nothing to grant to.
    private func requestStartupPermissions() async {
        guard world.owner.isSignedIn, world.hasPet else { return }
        if world.notifier.authorization == .notDetermined {
            await world.notifier.requestAuthorization()
        }
        if world.locator.authorization == .notDetermined {
            world.locator.requestAccess()
        }
    }
}

#Preview {
    ContentView()
        .environment(PetWorld.shared)
}
