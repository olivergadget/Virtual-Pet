import SwiftUI
import WatchKit

@main
struct PetWatchApp: App {
    @WKApplicationDelegateAdaptor(PetWatchDelegate.self) private var delegate
    @State private var store = PetWatchStore.shared
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            PetWatchHomeView()
                .environment(store)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: store.start()
            case .background: store.stop()
            default: break
            }
        }
    }
}

/// Exists for one reason: a pet arriving from the phone while nobody is looking at the
/// watch is delivered as a background task, and watchOS hands out a fixed budget of those.
/// Every task has to be marked finished or the budget runs out and the app gets killed, so
/// they are held here and completed once Watch Connectivity says it has nothing left to
/// give.
///
/// The work itself happens in ``PetSync``: the pet is saved and the complication reloaded
/// as a side effect of it arriving. This only has to keep the app alive long enough for
/// that, then tidy up.
final class PetWatchDelegate: NSObject, WKApplicationDelegate {
    private var pendingTasks: [WKWatchConnectivityRefreshBackgroundTask] = []

    func applicationDidFinishLaunching() {
        // The session has to be up before any background delivery arrives, which can be
        // well before the app's own scene appears.
        PetWatchStore.shared.start()
        PetSync.shared.onDelivery = { [weak self] in
            self?.completePendingTasks()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            if let connectivityTask = task as? WKWatchConnectivityRefreshBackgroundTask {
                pendingTasks.append(connectivityTask)
            } else {
                task.setTaskCompletedWithSnapshot(false)
            }
        }
        completePendingTasks()
    }

    /// Closes out the held tasks, but only once there is nothing still in flight — the
    /// first attempt usually lands while the pet is still arriving, which is why this is
    /// also called again from `PetSync` on every delivery.
    private func completePendingTasks() {
        guard !pendingTasks.isEmpty, !PetSync.shared.hasPendingContent else { return }
        let tasks = pendingTasks
        pendingTasks.removeAll()
        for task in tasks {
            task.setTaskCompletedWithSnapshot(false)
        }
    }
}
