import AVFoundation
import Foundation

/// Zero-asset procedural sci-fi UI audio synthesizer backed by `AVAudioEngine`.
/// Safely no-ops on environments without audio output hardware and respects `isMuted`.
public final class TelemetryAudio: @unchecked Sendable {
    public static let shared = TelemetryAudio()

    private enum SoundEffect: Hashable {
        case ping
        case modeSwitch
        case pin
    }

    private let stateLock = NSLock()
    private var _isMuted: Bool
    private var lastPlayedAt: [SoundEffect: CFAbsoluteTime] = [:]

    private let audioQueue = DispatchQueue(label: "com.antigravity.hud.audio", qos: .userInteractive)
    private let sampleRate: Double = 44_100
    private var engine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private var synthFormat: AVAudioFormat?
    private var cachedBuffers: [SoundEffect: AVAudioPCMBuffer] = [:]
    private var configObserver: NSObjectProtocol?
    private var idlePauseWorkItem: DispatchWorkItem?

    /// Thread-safe mute flag. Setting to `true` immediately halts queued playback.
    public var isMuted: Bool {
        get {
            stateLock.lock()
            defer { stateLock.unlock() }
            return _isMuted
        }
        set {
            stateLock.lock()
            _isMuted = newValue
            stateLock.unlock()
            if newValue {
                audioQueue.async { [weak self] in
                    self?.playerNode?.stop()
                    self?.engine?.pause()
                }
            }
        }
    }

    public init(isMuted: Bool = false) {
        self._isMuted = isMuted
    }

    deinit {
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        engine?.stop()
    }

    /// Subtle orbital radar ping for active agent pulses and priority alerts.
    public func playPing() {
        trigger(.ping, minInterval: 0.12)
    }

    /// Crisp dual-harmonic sweep for HUD mode and theme switches.
    public func playModeSwitch() {
        trigger(.modeSwitch, minInterval: 0.08)
    }

    /// Magnetic lock-on chime when pinning or unpinning a priority project.
    public func playPinSound() {
        trigger(.pin, minInterval: 0.08)
    }

    // MARK: - Playback Engine

    private func trigger(_ effect: SoundEffect, minInterval: CFAbsoluteTime) {
        let now = CFAbsoluteTimeGetCurrent()
        stateLock.lock()
        let muted = _isMuted
        let previous = lastPlayedAt[effect] ?? 0
        if muted || (now - previous) < minInterval {
            stateLock.unlock()
            return
        }
        lastPlayedAt[effect] = now
        stateLock.unlock()

        audioQueue.async { [weak self] in
            self?.playOnAudioQueue(effect)
        }
    }

    private func playOnAudioQueue(_ effect: SoundEffect) {
        guard !isMuted else { return }
        guard ensureEngineReady(),
              let engine,
              let playerNode,
              let buffer = buffer(for: effect) else {
            return
        }

        idlePauseWorkItem?.cancel()

        do {
            if !engine.isRunning {
                try engine.start()
            }
            playerNode.scheduleBuffer(buffer, at: nil, options: [], completionHandler: nil)
            if !playerNode.isPlaying {
                playerNode.play()
            }

            // Pause engine after idle window so audio hardware can sleep cleanly.
            let workItem = DispatchWorkItem { [weak self] in
                guard let self, let engine = self.engine else { return }
                if engine.isRunning {
                    engine.pause()
                }
            }
            idlePauseWorkItem = workItem
            audioQueue.asyncAfter(deadline: .now() + 6.0, execute: workItem)
        } catch {
            teardownEngine()
        }
    }

    private func ensureEngineReady() -> Bool {
        if let engine, playerNode != nil, synthFormat != nil {
            let hwFormat = engine.outputNode.outputFormat(forBus: 0)
            return hwFormat.sampleRate > 0 && hwFormat.channelCount > 0
        }

        let newEngine = AVAudioEngine()
        let hwFormat = newEngine.outputNode.outputFormat(forBus: 0)
        guard hwFormat.sampleRate > 0, hwFormat.channelCount > 0 else {
            return false
        }

        guard let format = AVAudioFormat(standardFormatWithSampleRate: sampleRate, channels: 1) else {
            return false
        }

        let node = AVAudioPlayerNode()
        newEngine.attach(node)
        newEngine.connect(node, to: newEngine.mainMixerNode, format: format)
        newEngine.mainMixerNode.outputVolume = 0.85

        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange,
            object: newEngine,
            queue: nil
        ) { [weak self] _ in
            self?.audioQueue.async { [weak self] in
                self?.teardownEngine()
            }
        }

        self.engine = newEngine
        self.playerNode = node
        self.synthFormat = format
        return true
    }

    private func teardownEngine() {
        idlePauseWorkItem?.cancel()
        idlePauseWorkItem = nil
        if let observer = configObserver {
            NotificationCenter.default.removeObserver(observer)
            configObserver = nil
        }
        playerNode?.stop()
        engine?.stop()
        playerNode = nil
        engine = nil
    }

    // MARK: - In-Memory Waveform Synthesis

    private func buffer(for effect: SoundEffect) -> AVAudioPCMBuffer? {
        if let existing = cachedBuffers[effect] {
            return existing
        }
        guard let format = synthFormat else { return nil }

        let generated: AVAudioPCMBuffer?
        switch effect {
        case .ping:
            generated = synthesizeBuffer(duration: 0.19, format: format) { t, duration in
                let freq = 1046.5 - 58.0 * (t / duration)
                let fundamental = sin(2.0 * .pi * freq * t)
                let shimmer = 0.28 * sin(2.0 * .pi * (freq * 2.0) * t)
                let env = envelope(t: t, attack: 0.004, decayRate: 21.0, duration: duration)
                return Float((fundamental + shimmer) * env * 0.14)
            }
        case .modeSwitch:
            generated = synthesizeBuffer(duration: 0.15, format: format) { t, duration in
                let progress = t / duration
                // Smooth FM frequency glide (C5 -> G5)
                let carrierFreq = 523.25 + 260.75 * smoothstep(progress)
                let modFreq = carrierFreq * 2.0
                let modIndex = 0.55 * exp(-t * 28.0)
                let phase = 2.0 * .pi * carrierFreq * t + modIndex * sin(2.0 * .pi * modFreq * t)
                let harmonic = 0.22 * sin(2.0 * .pi * (carrierFreq * 1.5) * t)
                let env = envelope(t: t, attack: 0.005, decayRate: 24.0, duration: duration)
                return Float((sin(phase) + harmonic) * env * 0.13)
            }
        case .pin:
            generated = synthesizeBuffer(duration: 0.17, format: format) { t, duration in
                // Crisp tactile lock click + resonant harmonic fifth (E5 + B5)
                let click = 0.45 * sin(2.0 * .pi * 1760.0 * t) * exp(-t * 140.0)
                let toneA = sin(2.0 * .pi * 659.25 * t)
                let toneB = 0.60 * sin(2.0 * .pi * 987.77 * t)
                let chimeEnv = envelope(t: t, attack: 0.003, decayRate: 22.0, duration: duration)
                return Float((click + (toneA + toneB) * 0.55 * chimeEnv) * 0.16)
            }
        }

        if let generated {
            cachedBuffers[effect] = generated
        }
        return generated
    }

    private func synthesizeBuffer(
        duration: Double,
        format: AVAudioFormat,
        sampleAt: (Double, Double) -> Float
    ) -> AVAudioPCMBuffer? {
        let frameCount = AVAudioFrameCount(duration * sampleRate)
        guard frameCount > 0,
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frameCount),
              let channelData = buffer.floatChannelData?[0] else {
            return nil
        }

        buffer.frameLength = frameCount
        for frame in 0..<Int(frameCount) {
            let t = Double(frame) / sampleRate
            channelData[frame] = sampleAt(t, duration)
        }
        return buffer
    }

    private func envelope(t: Double, attack: Double, decayRate: Double, duration: Double) -> Double {
        let attackGain = t < attack ? sin((t / attack) * (.pi * 0.5)) : 1.0
        let tailFade = t > (duration - 0.02) ? max(0.0, (duration - t) / 0.02) : 1.0
        return attackGain * exp(-max(0.0, t - attack) * decayRate) * tailFade
    }

    private func smoothstep(_ x: Double) -> Double {
        let clamped = min(max(x, 0.0), 1.0)
        return clamped * clamped * (3.0 - 2.0 * clamped)
    }
}
