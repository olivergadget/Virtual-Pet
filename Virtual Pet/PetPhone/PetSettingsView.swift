import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PetSettingsView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.openURL) private var openURL

    @State private var draftName = ""
    @State private var isConfirmingRelease = false

    var body: some View {
        @Bindable var world = world

        List {
            if let pet = world.pet {
                Section("Your pet") {
                    HStack {
                        Text("Name")
                        Spacer()
                        TextField("Name", text: $draftName)
                            .multilineTextAlignment(.trailing)
                            .submitLabel(.done)
                            .onSubmit { world.rename(to: draftName) }
                    }
                    Picker("Species", selection: speciesBinding(for: pet)) {
                        ForEach(PetKind.allCases) { kind in
                            Label(kind.displayName, systemImage: kind.symbolName).tag(kind)
                        }
                    }
                    LabeledContent("Adopted", value: pet.ageDescription)
                    LabeledContent("Bond", value: "Level \(pet.level) · \(pet.levelTitle)")
                    LabeledContent("Friends", value: "\(pet.friends.count)")
                }
            }

            Section {
                Toggle("Sound", isOn: $world.preferences.soundEnabled)
                Toggle("Play through silent mode", isOn: $world.preferences.overridesSilentSwitch)
                    .disabled(!world.preferences.soundEnabled)
                Toggle("Haptics", isOn: $world.preferences.hapticsEnabled)
            } header: {
                Text("Senses")
            } footer: {
                Text("Every purr, bark and meow is generated on the fly — the app contains no audio files.")
            }

            Section {
                Toggle("Nudges when neglected", isOn: $world.preferences.notificationsEnabled)
                permissionRow(
                    title: "Notification permission",
                    granted: world.notifier.isAuthorized,
                    grantedText: "Allowed",
                    action: { Task { await world.notifier.requestAuthorization() } }
                )
            } header: {
                Text("Notifications")
            } footer: {
                Text("Your pet sends a gentle nudge after 45 minutes, then escalates if it's ignored.")
            }

            Section {
                Toggle("Playdates with nearby pets", isOn: $world.preferences.nearbyEnabled)
                if world.social.isRunning {
                    LabeledContent("Status", value: "Looking for pets")
                }
            } header: {
                Text("Nearby")
            } footer: {
                Text("Uses the local network only. Nothing is uploaded and no account is needed.")
            }

            Section {
                permissionRow(
                    title: "Location permission",
                    granted: world.locator.isAuthorized,
                    grantedText: "While in use",
                    action: { world.locator.requestAccess() }
                )
                Button("Set den to here") {
                    world.setHomeHere()
                }
                .disabled(!world.locator.isAuthorized || world.locator.coordinate == nil)
                if let pet = world.pet, let status = world.locator.homeStatus(for: pet) {
                    Text(status)
                        .font(.footnote)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Home")
            } footer: {
                Text("Your pet uses a rough sense of home so it can tell when you're out. Coordinates stay on this device.")
            }

            if world.hasPet {
                Section {
                    Button("Say goodbye…", role: .destructive) {
                        isConfirmingRelease = true
                    }
                }
            }
        }
        .navigationTitle("Settings")
        .onAppear { draftName = world.pet?.name ?? "" }
        .onChange(of: world.preferences) { _, _ in
            world.applyPreferences()
        }
        .confirmationDialog(
            "Let \(world.pet?.name ?? "your pet") go?",
            isPresented: $isConfirmingRelease,
            titleVisibility: .visible
        ) {
            Button("Say goodbye", role: .destructive) {
                world.releasePet()
            }
            Button("Keep them", role: .cancel) {}
        } message: {
            Text("Their bond, friends and level are erased. You can adopt again straight away.")
        }
    }

    // MARK: Pieces

    private func speciesBinding(for pet: Pet) -> Binding<PetKind> {
        Binding(
            get: { pet.kind },
            set: { world.changeKind(to: $0) }
        )
    }

    @ViewBuilder
    private func permissionRow(
        title: String,
        granted: Bool,
        grantedText: String,
        action: @escaping () -> Void
    ) -> some View {
        HStack {
            Text(title)
            Spacer()
            if granted {
                Label(grantedText, systemImage: "checkmark.circle.fill")
                    .labelStyle(.titleAndIcon)
                    .font(.footnote)
                    .foregroundStyle(.green)
            } else {
                Button("Allow", action: action)
                    .font(.footnote.weight(.semibold))
                    .buttonStyle(.bordered)
                #if os(iOS)
                // Once the system stops prompting, Settings is the only way back.
                Button {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                } label: {
                    Image(systemName: "gear")
                }
                .buttonStyle(.borderless)
                .accessibilityLabel("Open Settings")
                #endif
            }
        }
    }
}
