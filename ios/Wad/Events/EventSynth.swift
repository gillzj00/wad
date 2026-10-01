import Foundation

/// The sounds of the shows, computed from sine waves, sawtooths and noise: no
/// recordings. Pure and deterministic, so the output can be checked. Mono
/// samples in -1...1 at `sampleRate`.
enum EventSynth {
    static let sampleRate = 44_100.0

    static func samples(for kind: GameEventKind) -> [Float] {
        var mix = Mix(duration: kind.duration)
        switch kind {
        case .wolfHoleWon: howl(&mix)
        case .greenie: bomb(&mix)
        case .wadTaken: moneyRain(&mix)
        case .skinWon: skinning(&mix)
        case .eagle: screech(&mix)
        case .holeInOne: fireworksAndCorks(&mix)
        case .albatross: thunderstorm(&mix)
        case .snowman: crumble(&mix)
        case .birdie: sadTrombone(&mix)
        }
        return mix.finished(peak: kind == .holeInOne ? 1 : 0.75, room: room(for: kind))
    }

    /// How much of a tail each sound gets: a howl in the hills, a thunderclap
    /// across a valley, a trombone in a bar.
    private static func room(for kind: GameEventKind) -> Double {
        switch kind {
        case .wolfHoleWon, .albatross, .holeInOne: 0.45
        case .greenie, .eagle, .snowman: 0.3
        case .wadTaken, .skinWon, .birdie: 0.18
        }
    }

    // MARK: Sounds

    /// A wolf: a rising, held and falling note with its harmonics and some breath.
    private static func howl(_ mix: inout Mix) {
        let pitch: (Double) -> Double = { t in
            switch t {
            case ..<0.7: return 300 + 320 * ease(t / 0.7)
            case ..<1.9: return 620 + 12 * sin(2 * .pi * 5.5 * t)
            default: return 620 - 250 * ease((t - 1.9) / 1.1)
            }
        }
        for harmonic in 1...6 {
            let level = 0.55 / pow(Double(harmonic), 1.3)
            mix.add(at: 0, Voice.tone(duration: 3, wave: .sine, frequency: { pitch($0) * Double(harmonic) }) {
                level * envelope($0, duration: 3, attack: 0.35, release: 0.6)
            })
        }
        for harmonic in 1...3 {
            let level = 0.25 / pow(Double(harmonic), 1.3)
            mix.add(at: 0.02, Voice.tone(duration: 3, wave: .sine, frequency: { pitch($0) * Double(harmonic) * 1.004 }) {
                level * envelope($0, duration: 3, attack: 0.35, release: 0.6)
            })
        }
        mix.add(at: 0, Voice.noise(duration: 3, cutoff: { _ in 1500 }) {
            0.05 * envelope($0, duration: 3, attack: 0.5, release: 0.8)
        })
        // A growl before the howl.
        mix.add(at: 0, Voice.tone(duration: 0.6, wave: .sawtooth, frequency: { 70 + 15 * sin(2 * .pi * 30 * $0) }, cutoff: { _ in 400 }) {
            0.5 * envelope($0, duration: 0.6, attack: 0.05, release: 0.2)
        })
    }

    /// A falling bomb whistle, then the blast, the ground and the crackle.
    private static func bomb(_ mix: inout Mix) {
        mix.add(at: 0, Voice.tone(duration: 1.5, wave: .sine, frequency: { 2400 - 1900 * ease($0 / 1.5) }) {
            0.04 + 0.26 * $0 / 1.5
        })
        mix.add(at: 1.5, Voice.noise(duration: 1.6, cutoff: { 4000 * exp(-$0 * 3) + 150 }) {
            0.95 * exp(-$0 * 2.2)
        })
        mix.add(at: 1.5, Voice.tone(duration: 1.2, wave: .sine, frequency: { 60 - 30 * min($0, 1) }) {
            0.9 * exp(-$0 * 2.5)
        })
        var rng = Rng(seed: 7)
        for _ in 0..<40 {
            let at = 1.7 + rng.next() * 1.6
            mix.add(at: at, Voice.noise(duration: 0.012, cutoff: { _ in 6000 }, rng: &rng) { _ in 0.25 * (2.9 - at) })
        }
    }

    /// A cash register bell, coins and a flutter of bills.
    private static func moneyRain(_ mix: inout Mix) {
        for (at, frequency) in [(0.0, 2637.0), (0.09, 3951.0)] {
            mix.add(at: at, Voice.tone(duration: 0.5, wave: .sine, frequency: { _ in frequency }) { 0.5 * exp(-$0 * 9) })
        }
        var rng = Rng(seed: 11)
        for _ in 0..<32 {
            let frequency = 3000 + rng.next() * 4000
            mix.add(at: 0.3 + rng.next() * 2.4, Voice.tone(duration: 0.12, wave: .sine, frequency: { _ in frequency }) {
                0.18 * exp(-$0 * 40)
            })
        }
        mix.add(at: 0.2, Voice.noise(duration: 2.6, cutoff: { _ in 3000 }, rng: &rng) {
            0.09 * abs(sin(2 * .pi * 9 * $0)) * envelope($0, duration: 2.6, attack: 0.2, release: 0.5)
        })
    }

    /// Five tears, each a modulated burst of noise, and a snap at the end.
    private static func skinning(_ mix: inout Mix) {
        var rng = Rng(seed: 3)
        for tear in 0..<5 {
            let at = 0.15 + Double(tear) * 0.36
            mix.add(at: at, Voice.noise(duration: 0.3, cutoff: { 700 + 3500 * $0 / 0.3 }, rng: &rng) {
                0.6 * (0.55 + 0.45 * sawtooth(40 * $0)) * envelope($0, duration: 0.3, attack: 0.02, release: 0.1)
            })
            mix.add(at: at, Voice.tone(duration: 0.3, wave: .sine, frequency: { 90 + 40 * sin(2 * .pi * 11 * $0) }) {
                0.25 * envelope($0, duration: 0.3, attack: 0.02, release: 0.1)
            })
        }
        mix.add(at: 2.0, Voice.noise(duration: 0.04, cutoff: { _ in 8000 }, rng: &rng) { _ in 0.8 })
        mix.add(at: 2.0, Voice.tone(duration: 0.3, wave: .sine, frequency: { _ in 150 }) { 0.6 * exp(-$0 * 15) })
    }

    /// Two screeches, with the wings between them.
    private static func screech(_ mix: inout Mix) {
        for at in [0.1, 1.3] {
            let length = 0.75
            mix.add(at: at, Voice.tone(duration: length, wave: .sawtooth, frequency: {
                2600 - 1000 * $0 / length + 120 * sin(2 * .pi * 28 * $0)
            }, cutoff: { _ in 5500 }) {
                0.3 * envelope($0, duration: length, attack: 0.03, release: 0.3)
            })
        }
        for at in [0.1, 1.3] {
            mix.add(at: at, Voice.noise(duration: 0.75, cutoff: { 3000 + 2000 * sin(2 * .pi * 28 * $0) }) {
                0.12 * envelope($0, duration: 0.75, attack: 0.03, release: 0.3)
            })
            mix.add(at: at, Voice.noise(duration: 0.02, cutoff: { _ in 9000 }) { _ in 0.5 })
        }
        mix.add(at: 0, Voice.noise(duration: 3, cutoff: { _ in 600 }) {
            0.14 * abs(sin(2 * .pi * 1.5 * $0)) * envelope($0, duration: 3, attack: 0.2, release: 0.6)
        })
    }

    /// Rockets whistling up and bursting, corks popping and fizzing, and the
    /// crackle of the bursts raining down.
    private static func fireworksAndCorks(_ mix: inout Mix) {
        var rng = Rng(seed: 19)
        for launch in [0.2, 1.4, 2.6, 3.7] {
            mix.add(at: launch, Voice.tone(duration: 0.7, wave: .sine, frequency: { 700 + 1300 * $0 / 0.7 }) {
                0.14 * envelope($0, duration: 0.7, attack: 0.05, release: 0.1)
            })
            let bang = launch + 0.75
            mix.add(at: bang, Voice.noise(duration: 1.0, cutoff: { 3000 * exp(-$0 * 4) + 200 }, rng: &rng) {
                0.9 * exp(-$0 * 3.5)
            })
            mix.add(at: bang, Voice.tone(duration: 0.8, wave: .sine, frequency: { 55 - 20 * min($0, 1) }) {
                0.8 * exp(-$0 * 3)
            })
        }
        for pop in [0.9, 2.1, 4.4] {
            mix.add(at: pop, Voice.tone(duration: 0.05, wave: .sine, frequency: { 420 - 300 * $0 / 0.05 }) { _ in 0.9 })
            mix.add(at: pop, Voice.noise(duration: 0.02, cutoff: { _ in 9000 }, rng: &rng) { _ in 0.7 })
            mix.add(at: pop + 0.05, Voice.noise(duration: 0.6, cutoff: { _ in 5000 }, rng: &rng) { 0.12 * exp(-$0 * 3) })
        }
        for _ in 0..<160 {
            let at = 1.0 + rng.next() * 4.9
            let level = 0.15 + rng.next() * 0.2
            mix.add(at: at, Voice.noise(duration: 0.004, cutoff: { _ in 7000 }, rng: &rng) { _ in level })
        }
    }

    /// Wind and wingbeats, a crack of thunder, its rumble and the flag ripping out.
    private static func thunderstorm(_ mix: inout Mix) {
        var rng = Rng(seed: 23)
        mix.add(at: 0, Voice.noise(duration: 4, cutoff: { _ in 400 }, rng: &rng) {
            0.14 * (0.6 + 0.4 * sin(2 * .pi * 0.7 * $0)) * envelope($0, duration: 4, attack: 0.3, release: 0.8)
        })
        mix.add(at: 0.4, Voice.noise(duration: 1.2, cutoff: { _ in 800 }, rng: &rng) {
            0.2 * max(0, sin(2 * .pi * 3 * $0))
        })
        mix.add(at: 1.6, Voice.noise(duration: 0.07, cutoff: { _ in 9000 }, rng: &rng) { _ in 1.0 })
        mix.add(at: 1.65, Voice.noise(duration: 2.3, cutoff: { _ in 120 }, rng: &rng) {
            0.9 * exp(-$0 * 1.1) * (0.7 + 0.3 * sin(2 * .pi * 2.3 * $0 + 1))
        })
        mix.add(at: 2.0, Voice.noise(duration: 0.25, cutoff: { 600 + 3000 * $0 / 0.25 }, rng: &rng) {
            0.5 * (0.5 + 0.5 * sawtooth(45 * $0)) * envelope($0, duration: 0.25, attack: 0.02, release: 0.08)
        })
    }

    /// A creak, cracks, the crumble and two thuds.
    private static func crumble(_ mix: inout Mix) {
        var rng = Rng(seed: 5)
        mix.add(at: 0.3, Voice.tone(duration: 0.35, wave: .sawtooth, frequency: { 90 - 30 * $0 / 0.35 }, cutoff: { _ in 500 }) {
            0.3 * envelope($0, duration: 0.35, attack: 0.05, release: 0.1)
        })
        for at in [0.7, 0.9, 1.0] {
            mix.add(at: at, Voice.noise(duration: 0.015, cutoff: { _ in 6000 }, rng: &rng) { _ in 0.6 })
        }
        for _ in 0..<60 {
            let at = 1.0 + pow(rng.next(), 1.5)
            mix.add(at: at, Voice.noise(duration: 0.008, cutoff: { _ in 3500 }, rng: &rng) { _ in 0.35 * (2.1 - at) })
        }
        for at in [1.1, 1.6] {
            mix.add(at: at, Voice.tone(duration: 0.4, wave: .sine, frequency: { 60 - 25 * min($0 / 0.4, 1) }) {
                0.9 * exp(-$0 * 7)
            })
        }
    }

    /// Four notes down the scale, the last one sagging: wah, wah, wah, waaah.
    private static func sadTrombone(_ mix: inout Mix) {
        let notes: [(at: Double, frequency: Double, length: Double)] = [
            (0.0, 466.2, 0.4), (0.45, 440.0, 0.4), (0.9, 415.3, 0.4), (1.35, 392.0, 1.1),
        ]
        for (index, note) in notes.enumerated() {
            let last = index == notes.count - 1
            mix.add(at: note.at, Voice.tone(duration: note.length, wave: .sawtooth, frequency: { t in
                let sag = last ? 1 - 0.1 * max(0, (t - 0.5) / 0.6) : 1 - 0.03 * t / note.length
                let vibrato = last ? 1 + 0.012 * sin(2 * .pi * 5 * t) : 1
                return note.frequency * sag * vibrato
            }, cutoff: { 2500 - 1700 * min($0 / 0.25, 1) }) {
                0.4 * envelope($0, duration: note.length, attack: 0.03, release: 0.1)
            })
            mix.add(at: note.at, Voice.noise(duration: note.length, cutoff: { _ in 1200 }) {
                0.04 * envelope($0, duration: note.length, attack: 0.05, release: 0.1)
            })
        }
        mix.add(at: 1.35, Voice.tone(duration: 0.5, wave: .sine, frequency: { _ in 65 }) { 0.5 * exp(-$0 * 6) })
    }

    // MARK: Building blocks

    enum Wave {
        case sine, sawtooth
    }

    /// Smooth 0...1 for 0...1.
    static func ease(_ x: Double) -> Double {
        let c = min(max(x, 0), 1)
        return c * c * (3 - 2 * c)
    }

    /// -1...1 at a rate of 1 per unit of `x`.
    static func sawtooth(_ x: Double) -> Double {
        2 * (x - floor(x)) - 1
    }

    /// 1 between a linear attack and a linear release, 0 outside the sound.
    static func envelope(_ t: Double, duration: Double, attack: Double, release: Double) -> Double {
        guard t >= 0, t <= duration else { return 0 }
        return min(1, t / attack, (duration - t) / release)
    }

    /// Deterministic: the same seed makes the same sound every time.
    struct Rng {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed &* 0x9E37_79B9_7F4A_7C15 | 1
        }

        /// 0..<1.
        mutating func next() -> Double {
            state ^= state << 13
            state ^= state >> 7
            state ^= state << 17
            return Double(state >> 11) / Double(1 << 53)
        }
    }

    /// One sound at a time, as samples.
    enum Voice {
        /// A waveform whose frequency and amplitude are functions of time, with
        /// an optional low-pass filter whose cutoff is as well.
        static func tone(
            duration: Double,
            wave: Wave,
            frequency: (Double) -> Double,
            cutoff: ((Double) -> Double)? = nil,
            amplitude: (Double) -> Double
        ) -> [Float] {
            let count = Int(duration * sampleRate)
            var phase = 0.0
            var out = [Float](repeating: 0, count: count)
            var filter = LowPass()
            for i in 0..<count {
                let t = Double(i) / sampleRate
                phase += frequency(t) / sampleRate
                phase -= floor(phase)
                var value = wave == .sine ? sin(2 * .pi * phase) : 2 * phase - 1
                if let cutoff { value = filter.process(value, cutoff: cutoff(t)) }
                out[i] = Float(value * amplitude(t))
            }
            return out
        }

        /// White noise through a low-pass filter.
        static func noise(duration: Double, cutoff: (Double) -> Double, amplitude: (Double) -> Double) -> [Float] {
            var rng = Rng(seed: 97)
            return noise(duration: duration, cutoff: cutoff, rng: &rng, amplitude: amplitude)
        }

        static func noise(
            duration: Double,
            cutoff: (Double) -> Double,
            rng: inout Rng,
            amplitude: (Double) -> Double
        ) -> [Float] {
            let count = Int(duration * sampleRate)
            var out = [Float](repeating: 0, count: count)
            var filter = LowPass()
            for i in 0..<count {
                let t = Double(i) / sampleRate
                let value = filter.process(rng.next() * 2 - 1, cutoff: cutoff(t))
                out[i] = Float(value * amplitude(t))
            }
            return out
        }
    }

    /// A one-pole low-pass filter.
    struct LowPass {
        private var last = 0.0

        mutating func process(_ x: Double, cutoff: Double) -> Double {
            let a = 1 - exp(-2 * .pi * max(cutoff, 1) / sampleRate)
            last += a * (x - last)
            return last
        }
    }

    /// The sounds summed, then kept within -1...1.
    struct Mix {
        private(set) var samples: [Float]

        init(duration: Double) {
            samples = [Float](repeating: 0, count: Int(duration * sampleRate))
        }

        mutating func add(at start: Double, _ voice: [Float]) {
            let offset = Int(start * sampleRate)
            guard offset < samples.count else { return }
            let count = min(voice.count, samples.count - offset)
            for i in 0..<count {
                samples[offset + i] += voice[i]
            }
        }

        /// With a tail from a few echoes (`room` 0 is dry), scaled so the
        /// loudest sample is at `peak`.
        func finished(peak: Float = 1, room: Double = 0) -> [Float] {
            var out = samples
            if room > 0 {
                // Three feedback delays at prime-ish spacings make a small hall.
                for delay in [0.0311, 0.0437, 0.0599] {
                    let d = Int(delay * sampleRate)
                    let feedback = Float(0.25 + room * 0.45)
                    var wet = [Float](repeating: 0, count: out.count)
                    for i in 0..<out.count {
                        let echo = i >= d ? wet[i - d] * feedback : 0
                        wet[i] = samples[i] + echo
                    }
                    let level = Float(room * 0.35)
                    for i in 0..<out.count {
                        out[i] += (wet[i] - samples[i]) * level
                    }
                }
            }
            let loudest = out.reduce(0) { max($0, abs($1)) }
            guard loudest > 0 else { return out }
            let gain = peak / loudest
            return out.map { $0 * gain }
        }
    }
}
