import Foundation
import Testing
@testable import Wad

/// The synthesized sounds: one per event, as long as its show, within range
/// and the same every time.
struct EventSynthTests {
    @Test(arguments: GameEventKind.allCases)
    func everySoundIsAsLongAsItsShowAndWithinRange(kind: GameEventKind) {
        let samples = EventSynth.samples(for: kind)
        #expect(samples.count == Int(kind.duration * EventSynth.sampleRate))
        #expect(samples.allSatisfy { $0 >= -1 && $0 <= 1 && $0.isFinite })
        // Not silence: something audible happens.
        let peak = samples.reduce(0) { max($0, abs($1)) }
        #expect(peak > 0.7, "\(kind) peaks at \(peak)")
    }

    @Test func theSameSoundEveryTime() {
        #expect(EventSynth.samples(for: .birdie) == EventSynth.samples(for: .birdie))
    }

    @Test func theHoleInOneIsTheLoudest() {
        func peak(_ kind: GameEventKind) -> Float {
            EventSynth.samples(for: kind).reduce(0) { max($0, abs($1)) }
        }
        #expect(abs(peak(.holeInOne) - 1) < 0.001)
        for kind in GameEventKind.allCases where kind != .holeInOne {
            #expect(peak(kind) < 0.8, "\(kind)")
        }
    }

    @Test func buildingBlocks() {
        #expect(EventSynth.ease(0) == 0)
        #expect(EventSynth.ease(1) == 1)
        #expect(EventSynth.ease(0.5) == 0.5)
        #expect(EventSynth.sawtooth(0.25) == -0.5)
        #expect(EventSynth.envelope(-1, duration: 2, attack: 0.1, release: 0.1) == 0)
        #expect(EventSynth.envelope(0.05, duration: 2, attack: 0.1, release: 0.1) == 0.5)
        #expect(EventSynth.envelope(1, duration: 2, attack: 0.1, release: 0.1) == 1)
        #expect(abs(EventSynth.envelope(1.95, duration: 2, attack: 0.1, release: 0.1) - 0.5) < 1e-9)

        var mix = EventSynth.Mix(duration: 0.01)
        mix.add(at: 0, [Float](repeating: 2, count: 10))
        mix.add(at: 1, [1])
        let finished = mix.finished(peak: 0.5)
        #expect(finished.count == 441)
        #expect(finished[0] == 0.5)
        #expect(finished[10] == 0)
    }
}
