import SwiftUI
import UserNotifications

@main
struct PetPhoneApp: App {
    @State private var world = PetWorld.shared
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Registered before the first scene appears so taps on a nudge are never dropped.
        UNUserNotificationCenter.current().delegate = PetNotificationRouter.shared
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(world)
        }
        .onChange(of: scenePhase) { _, phase in
            world.handleScenePhase(phase)
        }
    }
}
