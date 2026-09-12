import AVFAudio
import Foundation

/// Every noise the pet can make. Nothing here is a recording — the waveforms are
/// generated from scratch at launch, so the app ships without a single audio file.
enum PetSound: String, Sendable, CaseIterable {
    case purr
    case snuffle
    case meow
    case bark
    case yip
    case whine
    case chirp
    case trill
    case squeak
    case munch
    case growl
    case roar
    case thump

    /// Comfort sounds are built to loop seamlessly; the rest are one-shots.
    var isLoopable: Bool { self == .purr || self == .snuffle }
}

// MARK: - Synthesis

/// A tiny software synthesiser. Each function returns mono 32-bit float samples.
enum SoundSynth {
    static let sampleRate = 44_100.0

    static func samples(for sound: PetSound, voice: VoiceProfile) -> [Float] {
        switch sound {
        case .purr: purr(voice)
        case .snuffle: snuffle(voice)
        case .meow: meow(voice)
        case .bark: bark(voice, pitchScale: 1.0, duration: 0.30)
        case .yip: bark(voice, pitchScale: 1.8, duration: 0.17)
        case .whine: whine(voice)
        case .chirp: chirp(voice, pitchScale: 1.0)
        case .trill: trill(voice)
        case .squeak: squeak(voice)
        case .munch: munch(voice)
        case .growl: growl(voice)
        case .roar: roar(voice)
        case .thump: thump(voice)
        }
    }

    // MARK: Looping comfort sounds

    /// A purr is a low carrier chopped up by a slow amplitude pulse. The buffer holds a
    /// whole number of both cycles and starts and ends at silence, so looping is seamless.
    private static func purr(_ voice: VoiceProfile) -> [Float] {
        let rate = voice.purrRate
        let duration = 13 / rate
        let frames = Int(duration * sampleRate)
        // Snap the carrier to a whole number of cycles for a clean loop point.
        let carrierCycles = max((voice.purrPitch * duration).rounded(), 1)
        let carrier = carrierCycles / duration

        var output = [Float]()
        output.reserveCapacity(frames)
        var noise = WhiteNoise(seed: 0xC0FFEE)
        var rumbleFilter = OnePole(cutoff: 420)

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let pulse = pow(0.5 - 0.5 * cos(2 * .pi * rate * t), 1.7)
            let phase = 2 * .pi * carrier * t
            var sample = sin(phase) * 0.5 + sin(phase * 2) * 0.26 + sin(phase * 3) * 0.13
            sample += rumbleFilter.process(noise.next()) * 0.35
            output.append(Float(tanh(sample * 1.5) * pulse * 0.34))
        }
        return output
    }

    /// The dog's version of a purr: a contented groan with a breath on every cycle.
    private static func snuffle(_ voice: VoiceProfile) -> [Float] {
        let rate = max(voice.purrRate * 0.4, 1.2)
        let duration = 3 / rate
        let frames = Int(duration * sampleRate)
        let humCycles = max((voice.purrPitch * duration).rounded(), 1)
        let hum = humCycles / duration

        var output = [Float]()
        output.reserveCapacity(frames)
        var noise = WhiteNoise(seed: 0xBADA55)
        var breathFilter = OnePole(cutoff: 1_100)

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let pulse = pow(0.5 - 0.5 * cos(2 * .pi * rate * t), 2.0)
            let phase = 2 * .pi * hum * t
            var sample = sin(phase) * 0.45 + sin(phase * 2) * 0.2
            sample += breathFilter.process(noise.next()) * 0.55
            output.append(Float(tanh(sample * 1.3) * pulse * 0.3))
        }
        return output
    }

    // MARK: One-shot calls

    private static func meow(_ voice: VoiceProfile) -> [Float] {
        let duration = 0.85
        let frames = Int(duration * sampleRate)
        var output = [Float]()
        output.reserveCapacity(frames)
        var phase = 0.0
        var noise = WhiteNoise(seed: 0x5EED)

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let u = t / duration
            // Pitch arcs up into the "eee" and sags into the "ow".
            let arc = 0.88 + 0.44 * sin(.pi * min(u * 1.3, 1.0))
            let vibrato = 1 + 0.028 * sin(2 * .pi * 6.4 * t)
            phase += 2 * .pi * voice.pitch * arc * vibrato / sampleRate

            // The vowel opens in the middle of the call and closes at the end.
            let open = 0.35 + 0.65 * sin(.pi * u)
            var sample = sin(phase) * 0.55
            sample += sin(phase * 2) * 0.30 * open
            sample += sin(phase * 3) * 0.18 * open * voice.brightness
            sample += sin(phase * 4) * 0.09 * open * voice.brightness
            sample += noise.next() * 0.015 * open

            let envelope = attackRelease(u, attack: 0.14, release: 0.42)
            output.append(Float(sample * envelope * 0.45))
        }
        return output
    }

    private static func bark(_ voice: VoiceProfile, pitchScale: Double, duration: Double) -> [Float] {
        let frames = Int(duration * sampleRate)
        var output = [Float]()
        output.reserveCapacity(frames)
        var phase = 0.0
        var noise = WhiteNoise(seed: 0x1234ABCD)
        var burstFilter = OnePole(cutoff: 2_600)

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            // A hard consonant, then the body of the bark dropping away.
            let sweep = t < 0.05 ? 1.7 - t * 9 : max(1.25 - (t - 0.05) * 1.4, 0.6)
            phase += 2 * .pi * voice.pitch * pitchScale * sweep / sampleRate

            var sample = sin(phase) * 0.55 + sin(phase * 2) * 0.33
            sample += sin(phase * 3) * 0.2 * voice.brightness
            sample += burstFilter.process(noise.next()) * (t < 0.035 ? 0.55 : 0.12)

            let attack = min(t / 0.005, 1)
            let decay = exp(-t * (duration < 0.2 ? 15 : 9))
            output.append(Float(tanh(sample * 1.9) * attack * decay * 0.5))
        }
        return output
    }

    private static func whine(_ voice: VoiceProfile) -> [Float] {
        let duration = 1.05
        let frames = Int(duration * sampleRate)
        var output = [Float]()
        output.reserveCapacity(frames)
        var phase = 0.0

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let u = t / duration
            let arc = 0.92 + 0.5 * sin(.pi * u)
            let vibrato = 1 + 0.05 * sin(2 * .pi * 5.1 * t)
            phase += 2 * .pi * voice.pitch * arc * vibrato / sampleRate

            // Odd harmonics only: that is what makes it read as nasal and pleading.
            var sample = sin(phase) * 0.5
            sample += sin(phase * 3) * 0.22
            sample += sin(phase * 5) * 0.1 * voice.brightness

            let envelope = attackRelease(u, attack: 0.28, release: 0.38)
            output.append(Float(sample * envelope * 0.42))
        }
        return output
    }

    private static func chirp(_ voice: VoiceProfile, pitchScale: Double) -> [Float] {
        let duration = 0.17
        let frames = Int(duration * sampleRate)
        var output = [Float]()
        output.reserveCapacity(frames)
        var phase = 0.0

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let u = t / duration
            let sweep = 1.9 + 1.6 * u
            phase += 2 * .pi * voice.pitch * pitchScale * sweep / sampleRate
            let sample = sin(phase) * 0.7 + sin(phase * 2) * 0.2 * voice.brightness
            // Bell-shaped envelope keeps it soft at both ends.
            let envelope = exp(-pow((u - 0.45) * 3.1, 2) * 2)
            output.append(Float(sample * envelope * 0.4))
        }
        return output
    }

    /// Three ascending chirps: the happy "brrrp!" a cat makes walking into a room.
    private static func trill(_ voice: VoiceProfile) -> [Float] {
        var output = [Float]()
        for (index, scale) in [0.9, 1.12, 1.4].enumerated() {
            output += chirp(voice, pitchScale: scale)
            if index < 2 {
                output += [Float](repeating: 0, count: Int(0.035 * sampleRate))
            }
        }
        return output
    }

    private static func squeak(_ voice: VoiceProfile) -> [Float] {
        let duration = 0.2
        let frames = Int(duration * sampleRate)
        var output = [Float]()
        output.reserveCapacity(frames)
        var phase = 0.0

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let u = t / duration
            let wobble = 1 + 0.22 * sin(2 * .pi * 21 * t)
            phase += 2 * .pi * voice.pitch * 1.5 * wobble / sampleRate
            let sample = sin(phase) * 0.8 + sin(phase * 2) * 0.12
            let envelope = exp(-pow((u - 0.4) * 3.4, 2) * 2.4)
            output.append(Float(sample * envelope * 0.38))
        }
        return output
    }

    private static func munch(_ voice: VoiceProfile) -> [Float] {
        let bites = [0.0, 0.17, 0.34, 0.51]
        let duration = 0.72
        let frames = Int(duration * sampleRate)
        var output = [Float]()
        output.reserveCapacity(frames)
        var noise = WhiteNoise(seed: 0xFEEDFACE)
        var previous = 0.0

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            // Sum of sharp decays, one per bite.
            var envelope = 0.0
            for bite in bites where t >= bite {
                envelope += exp(-(t - bite) * 34)
            }
            envelope = min(envelope, 1)

            let raw = noise.next()
            // Differencing the noise brightens it into a crunch.
            let crunch = raw - previous
            previous = raw
            let thud = sin(2 * .pi * 95 * t) * 0.25
            output.append(Float((crunch * 0.7 + thud) * envelope * 0.4))
        }
        return output
    }

    private static func growl(_ voice: VoiceProfile) -> [Float] {
        let duration = 0.8
        let frames = Int(duration * sampleRate)
        var output = [Float]()
        output.reserveCapacity(frames)
        var noise = WhiteNoise(seed: 0x606060)
        var filter = OnePole(cutoff: 700)
        var phase = 0.0

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let u = t / duration
            phase += 2 * .pi * voice.purrPitch * 1.7 / sampleRate
            let flutter = 0.6 + 0.4 * sin(2 * .pi * 37 * t)
            var sample = sin(phase) * 0.45 + sin(phase * 2) * 0.3 + sin(phase * 3) * 0.18
            sample += filter.process(noise.next()) * 0.45
            let envelope = attackRelease(u, attack: 0.12, release: 0.3)
            output.append(Float(tanh(sample * 2.1) * flutter * envelope * 0.36))
        }
        return output
    }

    private static func roar(_ voice: VoiceProfile) -> [Float] {
        let duration = 1.15
        let frames = Int(duration * sampleRate)
        var output = [Float]()
        output.reserveCapacity(frames)
        var noise = WhiteNoise(seed: 0xDEAD_BEEF)
        var filter = OnePole(cutoff: 1_600)
        var phase = 0.0

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let u = t / duration
            let sweep = 1.15 - 0.5 * u
            phase += 2 * .pi * voice.pitch * sweep / sampleRate

            var sample = 0.0
            for harmonic in 1...6 {
                sample += sin(phase * Double(harmonic)) * (0.5 / Double(harmonic))
            }
            sample += filter.process(noise.next()) * 0.3
            let envelope = attackRelease(u, attack: 0.1, release: 0.45)
            output.append(Float(tanh(sample * 2.4) * envelope * 0.4))
        }
        return output
    }

    /// A rabbit's foot-thump: mostly body, barely any pitch.
    private static func thump(_ voice: VoiceProfile) -> [Float] {
        let duration = 0.26
        let frames = Int(duration * sampleRate)
        var output = [Float]()
        output.reserveCapacity(frames)
        var noise = WhiteNoise(seed: 0x7A7A7A)
        var phase = 0.0

        for frame in 0..<frames {
            let t = Double(frame) / sampleRate
            let sweep = 1.0 - 0.35 * (t / duration)
            phase += 2 * .pi * 82 * sweep / sampleRate
            var sample = sin(phase) * 0.9
            sample += noise.next() * (t < 0.012 ? 0.5 : 0.03)
            let envelope = exp(-t * 17)
            output.append(Float(tanh(sample * 1.4) * envelope * 0.55))
        }
        return output
    }

    // MARK: Building blocks

    private static func attackRelease(_ u: Double, attack: Double, release: Double) -> Double {
        let rise = u < attack ? u / attack : 1
        let fall = u > 1 - release ? max(1 - u, 0) / release : 1
        return pow(rise, 1.4) * pow(fall, 1.6)
    }

    /// Deterministic noise, so a given pet always sounds exactly the same.
    private struct WhiteNoise {
        private var state: UInt64

        init(seed: UInt64) {
            state = seed | 1
        }

        mutating func next() -> Double {
            state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
            let bits = Double((state >> 40) & 0xFF_FFFF)
            return bits / 8_388_608.0 - 1.0
        }
    }

    /// One-pole low-pass, used to take the fizz off the noise sources.
    private struct OnePole {
        private var previous = 0.0
        private let coefficient: Double

        init(cutoff: Double) {
            coefficient = exp(-2 * .pi * cutoff / SoundSynth.sampleRate)
        }

        mutating func process(_ input: Double) -> Double {
            previous = input * (1 - coefficient) + previous * coefficient
            return previous
        }
    }
}

// MARK: - Playback

/// Owns the audio engine and hands out pet noises. Buffers are synthesised once per
/// species and cached, so repeated meows cost nothing.
@MainActor
final class PetVoice {
    static let shared = PetVoice()

    var isEnabled = true
    /// When true the pet plays through the ringer switch, the way an alarm does.
    var overridesSilentSwitch = true {
        didSet {
            guard oldValue != overridesSilentSwitch else { return }
            configureSession()
        }
    }

    private let engine = AVAudioEngine()
    private let oneShots = AVAudioPlayerNode()
    private let comfortLoop = AVAudioPlayerNode()
    private let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 1)
    private var cache: [String: AVAudioPCMBuffer] = [:]
    private var isWired = false
    private var loopingSound: PetSound?

    private init() {}

    /// Starts (or restarts) the engine. Safe to call as often as you like.
    func activate() {
        guard isEnabled, let format else { return }
        configureSession()

        if !isWired {
            engine.attach(oneShots)
            engine.attach(comfortLoop)
            try? engine.connectNode(oneShots, to: engine.mainMixerNode, format: format)
            try? engine.connectNode(comfortLoop, to: engine.mainMixerNode, format: format)
            isWired = true
        }

        guard !engine.isRunning else { return }
        engine.prepare()
        do {
            try engine.start()
            try oneShots.playAudio()
            try comfortLoop.playAudio()
        } catch {
            // Sound is a bonus, not a requirement — the pet carries on silently.
        }
    }

    func deactivate() {
        stopComfortLoop()
        engine.pause()
    }

    func play(_ sound: PetSound, voice: VoiceProfile, volume: Float = 0.9) {
        guard isEnabled else { return }
        activate()
        guard engine.isRunning, let buffer = buffer(for: sound, voice: voice) else { return }
        oneShots.volume = volume
        // `.interrupts` keeps an over-excited pet from stacking up a queue of barks.
        oneShots.scheduleBuffer(buffer, at: nil, options: .interrupts, completionHandler: nil)
    }

    func startComfortLoop(_ sound: PetSound, voice: VoiceProfile, volume: Float = 0.8) {
        guard isEnabled else { return }
        activate()
        guard engine.isRunning, let buffer = buffer(for: sound, voice: voice) else { return }

        if loopingSound == sound {
            comfortLoop.volume = volume
            return
        }
        comfortLoop.stop()
        comfortLoop.volume = volume
        comfortLoop.scheduleBuffer(buffer, at: nil, options: .loops, completionHandler: nil)
        try? comfortLoop.playAudio()
        loopingSound = sound
    }

    func stopComfortLoop() {
        guard loopingSound != nil else { return }
        comfortLoop.stop()
        loopingSound = nil
        if engine.isRunning {
            try? comfortLoop.playAudio()
        }
    }

    var isPurring: Bool { loopingSound != nil }

    // MARK: Internals

    private func buffer(for sound: PetSound, voice: VoiceProfile) -> AVAudioPCMBuffer? {
        let key = [
            sound.rawValue,
            String(Int(voice.pitch)),
            String(Int(voice.purrPitch)),
            String(Int(voice.purrRate * 10)),
            String(Int(voice.brightness * 100))
        ].joined(separator: "|")

        if let cached = cache[key] { return cached }
        guard let format else { return nil }

        let samples = SoundSynth.samples(for: sound, voice: voice)
        guard !samples.isEmpty,
              let buffer = AVAudioPCMBuffer(pcmFormat: format,
                                            frameCapacity: AVAudioFrameCount(samples.count)),
              let channel = buffer.floatChannelData?[0]
        else { return nil }

        for index in samples.indices {
            channel[index] = samples[index]
        }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        cache[key] = buffer
        return buffer
    }

    private func configureSession() {
        #if os(iOS)
        let session = AVAudioSession.sharedInstance()
        let category: AVAudioSession.Category = overridesSilentSwitch ? .playback : .ambient
        try? session.setCategory(category, mode: .default, options: [.mixWithOthers])
        try? session.setActive(true)
        #endif
    }
}
