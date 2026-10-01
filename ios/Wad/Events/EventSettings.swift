import Foundation
import Observation

/// How an event is shown.
enum EventPlayback: Equatable, Sendable {
    /// The full show.
    case animated
    /// A still picture with the sound and the haptics: Reduce Motion is on.
    case still
    /// Nothing at all: the animations are switched off.
    case off
}

/// The switches for the shows, kept in UserDefaults.
@Observable
@MainActor
final class EventSettings {
    enum Key {
        static let soundsEnabled = "events.soundsEnabled"
        static let animationsEnabled = "events.animationsEnabled"
    }

    private let defaults: UserDefaults

    var soundsEnabled: Bool {
        didSet { defaults.set(soundsEnabled, forKey: Key.soundsEnabled) }
    }

    var animationsEnabled: Bool {
        didSet { defaults.set(animationsEnabled, forKey: Key.animationsEnabled) }
    }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        soundsEnabled = Self.flag(Key.soundsEnabled, in: defaults)
        animationsEnabled = Self.flag(Key.animationsEnabled, in: defaults)
    }

    /// Both switches are on until turned off.
    private static func flag(_ key: String, in defaults: UserDefaults) -> Bool {
        defaults.object(forKey: key) == nil ? true : defaults.bool(forKey: key)
    }

    func playback(reduceMotion: Bool) -> EventPlayback {
        Self.playback(animationsEnabled: animationsEnabled, reduceMotion: reduceMotion)
    }

    /// The animations switch wins; with it on, Reduce Motion gives a still picture.
    static func playback(animationsEnabled: Bool, reduceMotion: Bool) -> EventPlayback {
        guard animationsEnabled else { return .off }
        return reduceMotion ? .still : .animated
    }

    #if DEBUG
    /// `-debugAnimations off` plays nothing, so the UI tests score without
    /// waiting for the shows.
    static var isDisabledByLaunchArgument: Bool {
        UserDefaults.standard.string(forKey: LaunchArgument.debugAnimations) == "off"
    }
    #endif
}
