import SwiftUI

/// The switches for the shows, as a sheet from the rounds list.
struct EventSettingsView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            EventSettingsList()
                .navigationTitle("Settings")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
    }
}

/// The switches for the shows: in the sheet from the rounds list, and pushed
/// from the Profile tab.
struct EventSettingsList: View {
    @Environment(EventCenter.self) private var center

    var body: some View {
        @Bindable var settings = center.settings
        List {
            Section {
                Toggle("Animations", isOn: $settings.animationsEnabled)
                    .accessibilityIdentifier("settings.animations")
                Toggle("Sounds", isOn: $settings.soundsEnabled)
                    .disabled(!settings.animationsEnabled)
                    .accessibilityIdentifier("settings.sounds")
            } header: {
                SectionHeader("Celebrations", systemImage: "sparkles")
            } footer: {
                SectionFooter(
                    "A hole in one, an albatross, an eagle, a birdie, a snowman (an 8), a greenie, a skin, "
                        + "the Wad changing hands and a Wolf hole won each get a show on this phone, "
                        + "with sound and vibration. The silent switch mutes the sounds. "
                        + "With Reduce Motion on, each show is a still picture."
                )
            }
            .themedRows()
        }
        .themedList()
    }
}

#if DEBUG
#Preview {
    EventSettingsView()
        .environment(EventCenter())
}
#endif
