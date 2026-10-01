import Foundation

/// The events waiting for their turn on screen: one plays at a time, the rest
/// wait in priority order. Pure; `EventCenter` drives it.
struct EventQueueState: Equatable, Sendable {
    private(set) var current: GameEvent?
    private(set) var pending: [GameEvent] = []

    /// Adds the events that are not already playing or waiting, keeps the
    /// waiting ones in priority order and starts the first if nothing plays.
    mutating func enqueue(_ events: [GameEvent]) {
        for event in events where event != current && !pending.contains(event) {
            pending.append(event)
        }
        pending = EventOrder.sorted(pending, players: [])
        if current == nil {
            advance()
        }
    }

    /// Ends the current event, by tap or by its clock, and starts the next.
    mutating func advance() {
        current = pending.isEmpty ? nil : pending.removeFirst()
    }

    mutating func clear() {
        current = nil
        pending.removeAll()
    }
}
