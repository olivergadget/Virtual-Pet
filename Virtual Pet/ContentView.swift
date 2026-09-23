import SwiftUI

/// Root router: adoption flow until there's a pet, then the four tabs.
struct ContentView: View {
    @Environment(PetWorld.self) private var world

    var body: some View {
        Group {
            if world.hasPet {
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
            await world.start()
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
    private func requestStartupPermissions() async {
        guard world.hasPet else { return }
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
