import Foundation
import Testing
@testable import Wad

/// The sound and animation switches, and what Reduce Motion makes of them.
@MainActor
struct EventSettingsTests {
    let suite = "EventSettingsTests.\(UUID().uuidString)"
    let defaults: UserDefaults

    init() throws {
        defaults = try #require(UserDefaults(suiteName: suite))
    }

    @Test func bothSwitchesStartOn() {
        let settings = EventSettings(defaults: defaults)
        #expect(settings.soundsEnabled)
        #expect(settings.animationsEnabled)
    }

    @Test func switchesPersistAcrossInstances() {
        let settings = EventSettings(defaults: defaults)
        settings.soundsEnabled = false
        #expect(EventSettings(defaults: defaults).soundsEnabled == false)
        #expect(EventSettings(defaults: defaults).animationsEnabled)

        settings.animationsEnabled = false
        settings.soundsEnabled = true
        let reloaded = EventSettings(defaults: defaults)
        #expect(reloaded.animationsEnabled == false)
        #expect(reloaded.soundsEnabled)
    }

    @Test func reduceMotionGivesAStillPictureUnlessAnimationsAreOff() {
        #expect(EventSettings.playback(animationsEnabled: true, reduceMotion: false) == .animated)
        #expect(EventSettings.playback(animationsEnabled: true, reduceMotion: true) == .still)
        #expect(EventSettings.playback(animationsEnabled: false, reduceMotion: false) == .off)
        #expect(EventSettings.playback(animationsEnabled: false, reduceMotion: true) == .off)

        let settings = EventSettings(defaults: defaults)
        #expect(settings.playback(reduceMotion: true) == .still)
        settings.animationsEnabled = false
        #expect(settings.playback(reduceMotion: true) == .off)
    }
}
