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

    /// Set by `LiveCenter` while the round is shared live: called with the
    /// events a change newly triggered, which are then not queued here. The
    /// shows taunt the opponents on the phones following the round, not the
    /// scorer. Events that arrive from the network go through `enqueue`,
    /// never through here.
    @ObservationIgnored var relay: (([GameEvent]) -> Void)?
    /// With `relay`: the scores the change set or cleared.
    @ObservationIgnored var relayScores: (([ScoreChange]) -> Void)?

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

    /// Changes are detected for the shows, or to relay them while sharing
    /// live with the shows switched off.
    private var detects: Bool { isEnabled || relay != nil }

    /// The state to compare against, taken before a change to the round.
    func snapshot(of round: Round) -> GameSnapshot? {
        guard detects else { return nil }
        return GameSnapshot(round: round)
    }

    /// After the change: what newly appeared since `before` is relayed while
    /// sharing live, with the scores, and played here only when not sharing.
    func record(_ round: Round, before: GameSnapshot?) {
        guard let before, detects else { return }
        let after = GameSnapshot(round: round)
        let events = EventDetector.events(before: before, after: after)
        if let relay {
            relayScores?(ScoreDetector.changes(before: before, after: after))
            relay(events)
        } else if isEnabled {
            enqueue(events)
        }
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
