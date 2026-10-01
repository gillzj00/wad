import CoreHaptics
import Foundation
import UIKit

/// A haptic pattern per event, scaled to it: a hole in one shakes the phone
/// for seconds, a birdie is a tap. CoreHaptics when the device has it, the
/// UIKit feedback generators otherwise.
@MainActor
final class EventHaptics {
    private var engine: CHHapticEngine?
    private var player: CHHapticPatternPlayer?
    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics

    func play(_ kind: GameEventKind) {
        if supportsHaptics, let pattern = try? CHHapticPattern(events: Self.events(for: kind), parameters: []) {
            do {
                let engine = try runningEngine()
                try self.player?.cancel()
                let player = try engine.makePlayer(with: pattern)
                try player.start(atTime: CHHapticTimeImmediate)
                self.player = player
                return
            } catch {
                // Fall through to the generators.
            }
        }
        fallback(kind)
    }

    /// Cuts the pattern short, when the show is dismissed.
    func stop() {
        try? player?.cancel()
        player = nil
    }

    private func runningEngine() throws -> CHHapticEngine {
        if let engine { return engine }
        let engine = try CHHapticEngine()
        engine.resetHandler = { [weak self] in
            Task { @MainActor in self?.engine = nil }
        }
        engine.stoppedHandler = { [weak self] _ in
            Task { @MainActor in self?.engine = nil }
        }
        try engine.start()
        self.engine = engine
        return engine
    }

    /// The pattern of each show, in seconds from its start.
    static func events(for kind: GameEventKind) -> [CHHapticEvent] {
        switch kind {
        case .holeInOne:
            // A long rumble, then a bang per firework and a knock per cork.
            var events = [continuous(at: 0, duration: 1.5, intensity: 0.7, sharpness: 0.3)]
            for bang in [0.95, 2.15, 3.35, 4.45] {
                events.append(transient(at: bang, intensity: 1, sharpness: 0.8))
                events.append(continuous(at: bang, duration: 0.5, intensity: 0.8, sharpness: 0.2))
            }
            for pop in [0.9, 2.1, 4.4] {
                events.append(transient(at: pop, intensity: 0.9, sharpness: 1))
            }
            events.append(continuous(at: 5.0, duration: 1.0, intensity: 0.5, sharpness: 0.4))
            return events
        case .albatross:
            return [
                continuous(at: 0.4, duration: 1.0, intensity: 0.4, sharpness: 0.2),
                transient(at: 1.6, intensity: 1, sharpness: 0.9),
                continuous(at: 1.65, duration: 2.0, intensity: 0.8, sharpness: 0.1),
            ]
        case .eagle:
            return [
                transient(at: 0.1, intensity: 0.9, sharpness: 0.9),
                transient(at: 1.3, intensity: 0.9, sharpness: 0.9),
                continuous(at: 0, duration: 2.5, intensity: 0.3, sharpness: 0.5),
            ]
        case .greenie:
            return [
                continuous(at: 0, duration: 1.5, intensity: 0.3, sharpness: 0.9),
                transient(at: 1.5, intensity: 1, sharpness: 0.6),
                continuous(at: 1.5, duration: 1.2, intensity: 0.9, sharpness: 0.1),
            ]
        case .wadTaken:
            return (0..<12).map { transient(at: 0.3 + Double($0) * 0.2, intensity: 0.6, sharpness: 0.9) }
        case .skinWon:
            return (0..<5).map { continuous(at: 0.15 + Double($0) * 0.36, duration: 0.25, intensity: 0.7, sharpness: 0.8) }
                + [transient(at: 2.0, intensity: 1, sharpness: 1)]
        case .wolfHoleWon:
            return [
                transient(at: 0.3, intensity: 0.8, sharpness: 0.7),
                continuous(at: 0.7, duration: 2.0, intensity: 0.6, sharpness: 0.3),
            ]
        case .snowman:
            return [
                transient(at: 0.7, intensity: 0.5, sharpness: 0.8),
                transient(at: 0.9, intensity: 0.5, sharpness: 0.8),
                transient(at: 1.1, intensity: 1, sharpness: 0.3),
                transient(at: 1.6, intensity: 0.9, sharpness: 0.3),
            ]
        case .birdie:
            return [0.0, 0.45, 0.9, 1.35].map { transient(at: $0, intensity: 0.5, sharpness: 0.5) }
        }
    }

    private static func transient(at time: TimeInterval, intensity: Float, sharpness: Float) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticTransient,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time
        )
    }

    private static func continuous(
        at time: TimeInterval, duration: TimeInterval, intensity: Float, sharpness: Float
    ) -> CHHapticEvent {
        CHHapticEvent(
            eventType: .hapticContinuous,
            parameters: [
                CHHapticEventParameter(parameterID: .hapticIntensity, value: intensity),
                CHHapticEventParameter(parameterID: .hapticSharpness, value: sharpness),
            ],
            relativeTime: time,
            duration: duration
        )
    }

    /// The generators do one buzz at a time; a hole in one gets a few.
    private func fallback(_ kind: GameEventKind) {
        switch kind {
        case .holeInOne:
            UINotificationFeedbackGenerator().notificationOccurred(.success)
            for delay in [0.3, 0.6, 0.9, 1.2] {
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(delay))
                    UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
                }
            }
        case .albatross, .eagle, .greenie, .wolfHoleWon:
            UIImpactFeedbackGenerator(style: .heavy).impactOccurred()
        case .wadTaken, .skinWon, .snowman:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        case .birdie:
            UIImpactFeedbackGenerator(style: .light).impactOccurred()
        }
    }
}
