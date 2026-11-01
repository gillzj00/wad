import Foundation
import Observation

/// The phone owner's name, handicap index and Venmo handle, as typed. Nothing
/// is validated here: setup validates what it copies into a round.
struct Profile: Equatable, Sendable {
    var name = ""
    var handicapIndexText = ""
    var venmoHandleText = ""

    var trimmedName: String { name.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedHandicapIndexText: String { handicapIndexText.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedVenmoHandleText: String { venmoHandleText.trimmingCharacters(in: .whitespacesAndNewlines) }

    var isEmpty: Bool {
        trimmedName.isEmpty && trimmedHandicapIndexText.isEmpty && trimmedVenmoHandleText.isEmpty
    }
}

/// The profile, kept on the phone in UserDefaults. Each field is saved as it
/// changes, so partial input is never lost. Local only until sign-in (M1.1).
@Observable
@MainActor
final class ProfileStore {
    enum Key {
        static let name = "profile.name"
        static let handicapIndexText = "profile.handicapIndexText"
        static let venmoHandleText = "profile.venmoHandleText"
    }

    private let defaults: UserDefaults

    var name: String {
        didSet { defaults.set(name, forKey: Key.name) }
    }

    var handicapIndexText: String {
        didSet { defaults.set(handicapIndexText, forKey: Key.handicapIndexText) }
    }

    var venmoHandleText: String {
        didSet { defaults.set(venmoHandleText, forKey: Key.venmoHandleText) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        name = defaults.string(forKey: Key.name) ?? ""
        handicapIndexText = defaults.string(forKey: Key.handicapIndexText) ?? ""
        venmoHandleText = defaults.string(forKey: Key.venmoHandleText) ?? ""
    }

    var profile: Profile {
        Profile(name: name, handicapIndexText: handicapIndexText, venmoHandleText: venmoHandleText)
    }

    /// The standard defaults, except with `-inMemoryStore`: then the profile
    /// starts empty on every launch like the rounds, so the UI tests never see
    /// a profile typed on the simulator.
    static func launchDefaults() -> UserDefaults {
        let suite = "com.gillzj00.wad.inMemoryProfile"
        guard
            ProcessInfo.processInfo.arguments.contains(LaunchArgument.inMemoryStore),
            let defaults = UserDefaults(suiteName: suite)
        else { return .standard }
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }
}

extension RoundDraft {
    /// The draft with its first player filled in from the profile: name,
    /// handicap index and Venmo handle, as text, for setup to validate. The
    /// other players stay as they are, and an empty profile changes nothing.
    func prefilled(from profile: Profile) -> RoundDraft {
        guard !profile.isEmpty, !players.isEmpty else { return self }
        var draft = self
        draft.players[0].name = profile.trimmedName
        draft.players[0].handicapIndexText = profile.trimmedHandicapIndexText
        draft.players[0].venmoHandleText = profile.trimmedVenmoHandleText
        return draft
    }
}
