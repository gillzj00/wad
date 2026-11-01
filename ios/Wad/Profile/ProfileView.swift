import SwiftUI

/// The Profile tab: the phone owner's name, handicap index and Venmo handle,
/// kept on the phone, and the settings of the shows.
struct ProfileView: View {
    @Environment(ProfileStore.self) private var store

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $store.name, prompt: .prompt("Name"))
                        .textInputAutocapitalization(.words)
                        .autocorrectionDisabled()
                        .accessibilityIdentifier("profile.name")
                    NumberRow(
                        title: "Handicap index",
                        prompt: "15.4",
                        text: $store.handicapIndexText,
                        keyboard: .numbersAndPunctuation,
                        identifier: "profile.handicapIndex"
                    )
                    LabeledContent("Venmo") {
                        TextField("Optional", text: $store.venmoHandleText, prompt: .prompt("Optional"))
                            .keyboardType(.asciiCapable)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.never)
                            .multilineTextAlignment(.trailing)
                            .accessibilityIdentifier("profile.venmo")
                    }
                } header: {
                    SectionHeader("You", systemImage: "person.fill")
                } footer: {
                    SectionFooter(
                        "Your name, handicap index and Venmo handle fill in the first player of a new round, "
                            + "where they can still be changed. The Venmo handle is used to pay or request "
                            + "when a round is settled. Kept on this phone only."
                    )
                }
                .themedRows()

                if !advisories.isEmpty {
                    Section {
                        ForEach(advisories, id: \.self) { message in
                            Label(message, systemImage: "exclamationmark.triangle.fill")
                                .foregroundStyle(Theme.Palette.blood)
                                .accessibilityElement(children: .ignore)
                                .accessibilityLabel(message)
                        }
                        .listRowBackground(WarningRowBackground())
                    }
                }

                Section {
                    NavigationLink("Shows") {
                        EventSettingsList()
                            .navigationTitle("Shows")
                            .navigationBarTitleDisplayMode(.inline)
                    }
                    .accessibilityIdentifier("profile.shows")
                } header: {
                    SectionHeader("Shows", systemImage: "sparkles")
                }
                .themedRows()
            }
            .themedList()
            .navigationTitle("Profile")
        }
    }

    /// What does not look right yet. Advisory only: the text is kept as typed,
    /// and setup checks what it copies into a round.
    private var advisories: [String] {
        Self.advisories(for: store.profile)
    }

    static let handicapIndexAdvice = "A handicap index is a number up to 54.0, such as 15.4 (or +1.2)."

    static func advisories(for profile: Profile) -> [String] {
        var messages: [String] = []
        if !profile.trimmedHandicapIndexText.isEmpty, SetupText.handicapIndex(profile.handicapIndexText) == nil {
            messages.append(handicapIndexAdvice)
        }
        if VenmoHandle.parse(profile.venmoHandleText) == .invalid {
            messages.append(VenmoHandle.rule)
        }
        return messages
    }
}

#if DEBUG
#Preview {
    ProfileView()
        .environment(ProfileStore(defaults: UserDefaults(suiteName: "preview.profile")!))
        .environment(EventCenter())
}
#endif
