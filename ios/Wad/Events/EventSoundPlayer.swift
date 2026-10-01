import AVFoundation
import Foundation

/// Plays the synthesized sounds through AVAudioEngine. The audio session is
/// ambient, so the silent switch mutes them and other audio keeps playing.
@MainActor
final class EventSoundPlayer {
    private let engine = AVAudioEngine()
    private let player = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: EventSynth.sampleRate, channels: 1)
    private var buffers: [GameEventKind: AVAudioPCMBuffer] = [:]
    private var warming: Task<Void, Never>?

    init() {
        engine.attach(player)
        if let format {
            engine.connect(player, to: engine.mainMixerNode, format: format)
        }
    }

    /// Synthesizes every sound in the background, so the first show does not wait.
    func prewarm() {
        guard warming == nil else { return }
        warming = Task(priority: .utility) { [weak self] in
            for kind in GameEventKind.allCases {
                let samples = await Task.detached(priority: .utility) { EventSynth.samples(for: kind) }.value
                guard let self, buffers[kind] == nil else { continue }
                buffers[kind] = buffer(from: samples)
            }
        }
    }

    func play(_ kind: GameEventKind) {
        guard let buffer = buffers[kind] ?? buffer(from: EventSynth.samples(for: kind)) else { return }
        buffers[kind] = buffer
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.ambient, options: [.mixWithOthers])
            try session.setActive(true)
            if !engine.isRunning {
                try engine.start()
            }
        } catch {
            return
        }
        player.stop()
        player.scheduleBuffer(buffer, at: nil)
        player.play()
    }

    func stop() {
        player.stop()
    }

    private func buffer(from samples: [Float]) -> AVAudioPCMBuffer? {
        guard
            let format,
            let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
            let channel = buffer.floatChannelData?[0]
        else { return nil }
        samples.withUnsafeBufferPointer { source in
            channel.update(from: source.baseAddress!, count: samples.count)
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        return buffer
    }
}
