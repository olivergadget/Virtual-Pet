import SwiftUI
#if os(iOS)
import UIKit
#endif

struct PetSettingsView: View {
    @Environment(PetWorld.self) private var world
    @Environment(\.openURL) private var openURL

    @State private var draftName = ""
    @State private var isConfirmingRelease = false
    /// The icon set on the Home Screen. Read from the system rather than observed, so it is
    /// refreshed by hand whenever the icon might have changed.
    @State private var iconName: String?

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
                    NavigationLink {
                        PetDesignScreen()
                    } label: {
                        LabeledContent {
                            Text("\(pet.kind.displayName) · \(pet.appearance.size.displayName)")
                        } label: {
                            Label("Design", systemImage: "paintpalette.fill")
                        }
                    }
                    LabeledContent("Adopted", value: pet.ageDescription)
                    LabeledContent("Bond", value: "Level \(pet.level) · \(pet.levelTitle)")
                    LabeledContent("Friends", value: "\(pet.friends.count)")
                }

                if PetAppIcon.isSupported {
                    let isMatching = iconName == PetAppIcon.name(for: pet)

                    Section {
                        Button {
                            Task {
                                await PetAppIcon.set(pet)
                                iconName = PetAppIcon.currentName
                            }
                        } label: {
                            LabeledContent {
                                if isMatching {
                                    Label("Matches", systemImage: "checkmark.circle.fill")
                                        .labelStyle(.titleAndIcon)
                                        .font(.footnote)
                                        .foregroundStyle(.green)
                                } else {
                                    Text("Use current look")
                                }
                            } label: {
                                Label("Home Screen icon", systemImage: "square.grid.2x2.fill")
                            }
                        }
                        .disabled(isMatching)
                    } header: {
                        Text("App icon")
                    } footer: {
                        Text("The icon changes species with your pet on its own. Recolour them and it needs this nudge, because iOS puts an alert on screen every time the icon changes. The closest of the ready-made coat colours is used.")
                    }
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

            if let pet = world.pet {
                Section {
                    Toggle("Sleeps when you sleep", isOn: $world.schedule.sleepEnabled)
                    if world.schedule.sleepEnabled {
                        DatePicker("Lights out",
                                   selection: time($world.schedule.sleepStart),
                                   displayedComponents: .hourAndMinute)
                        DatePicker("Up and about",
                                   selection: time($world.schedule.sleepEnd),
                                   displayedComponents: .hourAndMinute)
                    }
                    Toggle("Waits while you're out", isOn: $world.schedule.awayEnabled)
                    if world.schedule.awayEnabled {
                        DatePicker("Work or school",
                                   selection: time($world.schedule.awayStart),
                                   displayedComponents: .hourAndMinute)
                        DatePicker("Home again",
                                   selection: time($world.schedule.awayEnd),
                                   displayedComponents: .hourAndMinute)
                        Toggle("Weekends as well", isOn: $world.schedule.awayEveryDay)
                    }
                    LabeledContent("Right now") {
                        Label(pet.phase.label, systemImage: pet.phase.symbolName)
                            .labelStyle(.titleAndIcon)
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Your day")
                } footer: {
                    Text("\(pet.name) keeps your hours. Needs barely move overnight, and drift slowly while you're at work or school, so a full night's sleep and a full day out still leave a pet you can put right in a few minutes. Nothing here ever runs the meters flat.")
                }
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
                Text("Your pet sends a gentle nudge after 45 minutes, then escalates if it's ignored. Nothing is sent while it's asleep — anything that comes due overnight waits for the morning, and only the last of it is sent.")
            }

            Section {
                Toggle("Playdates with nearby pets", isOn: $world.preferences.nearbyEnabled)
                Toggle("Share postcards", isOn: $world.preferences.postcardsEnabled)
                    .disabled(!world.preferences.nearbyEnabled)
                NavigationLink {
                    GroupsView()
                } label: {
                    LabeledContent {
                        Text("\(world.groups.groups(containing: world.myPetID ?? "").count)")
                    } label: {
                        Label("Groups", systemImage: "person.2.fill")
                    }
                }
                if world.social.isRunning {
                    LabeledContent("Status", value: "Looking for pets")
                }
            } header: {
                Text("Nearby")
            } footer: {
                Text("Uses the local network only. Nothing is uploaded and no account is needed. With postcards off you can still make them — they just stay on this phone.")
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
        .onAppear {
            draftName = world.pet?.name ?? ""
            iconName = PetAppIcon.currentName
        }
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

    /// A `DatePicker` deals in dates; the schedule stores plain minutes past midnight so
    /// that bedtime still means bedtime after a flight. Today's date carries the time
    /// across between the two.
    private func time(_ minutes: Binding<Int>) -> Binding<Date> {
        Binding {
            PetSchedule.time(forMinute: minutes.wrappedValue)
        } set: { picked in
            minutes.wrappedValue = PetSchedule.minute(of: picked)
        }
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
