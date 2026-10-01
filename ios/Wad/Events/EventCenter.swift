import Foundation
import Observation

/// Runs the shows: finds the events a change to a round triggers, queues
/// them, and starts the sound and the haptics of each as it comes on screen.
/// One per app, in the environment; `EventOverlay` shows `current`.
@Observable
@MainActor
final class EventCenter {
    let settings: EventSettings
    private(set) var queue = EventQueueState()

    @ObservationIgnored private let sounds = EventSoundPlayer()
    @ObservationIgnored private let haptics = EventHaptics()

    init(settings: EventSettings = EventSettings()) {
        self.settings = settings
        if isEnabled {
            sounds.prewarm()
        }
    }

    var current: GameEvent? { queue.current }

    /// Nothing is detected or shown with the animations switched off, or
    /// under `-debugAnimations off`.
    var isEnabled: Bool {
        #if DEBUG
        if EventSettings.isDisabledByLaunchArgument { return false }
        #endif
        return settings.animationsEnabled
    }

    /// The state to compare against, taken before a change to the round.
    func snapshot(of round: Round) -> GameSnapshot? {
        guard isEnabled else { return nil }
        return GameSnapshot(round: round)
    }

    /// After the change: plays what newly appeared since `before`.
    func record(_ round: Round, before: GameSnapshot?) {
        guard let before, isEnabled else { return }
        enqueue(EventDetector.events(before: before, after: GameSnapshot(round: round)))
    }

    func enqueue(_ events: [GameEvent]) {
        let previous = queue.current
        queue.enqueue(events)
        if queue.current != previous {
            began(queue.current)
        }
    }

    /// Ends the current show, by tap or by its clock.
    func dismiss() {
        queue.advance()
        began(queue.current)
    }

    private func began(_ event: GameEvent?) {
        sounds.stop()
        haptics.stop()
        guard let event else { return }
        if settings.soundsEnabled {
            sounds.play(event.kind)
        }
        haptics.play(event.kind)
    }
}
