import SwiftUI

/// Root router: adoption flow until there's a pet, then the three tabs.
struct ContentView: View {
    @Environment(PetWorld.self) private var world

    var body: some View {
        Group {
            if world.hasPet {
                TabView {
                    Tab("Pet", systemImage: "heart.fill") {
                        PetHomeView()
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
        .task {
            await world.start()
            await requestStartupPermissions()
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
