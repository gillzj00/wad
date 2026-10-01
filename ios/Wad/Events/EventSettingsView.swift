import SwiftUI

/// The switches for the shows, as a sheet from the rounds list.
struct EventSettingsView: View {
    @Environment(EventCenter.self) private var center
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        @Bindable var settings = center.settings
        NavigationStack {
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
                        "Birdies, eagles, greenies, skins and the Wad changing hands get a show on this phone, "
                            + "with sound and vibration. The silent switch mutes the sounds. "
                            + "With Reduce Motion on, each show is a still picture."
                    )
                }
                .themedRows()
            }
            .themedList()
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

#if DEBUG
#Preview {
    EventSettingsView()
        .environment(EventCenter())
}
#endif
