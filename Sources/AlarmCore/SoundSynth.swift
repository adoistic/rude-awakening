import Foundation

/// Builds every alarm sound from scratch: oscillators, filters, envelopes and a pinch of noise.
/// The output is a mono loop at 44.1 kHz, already mastered to be as loud as it can be without clipping.
public enum SoundSynth {
    public static let sampleRate: Double = 44_100

    public static func render(_ id: String) -> [Float] {
        master(raw(id))
    }

    static func raw(_ id: String) -> [Double] {
        switch id {
        case "airhorn": return airhorn()
        case "goose": return goose()
        case "klaxon": return klaxon()
        case "microwave": return microwave()
        case "siren": return siren()
        case "rooster": return rooster()
        case "robot": return robot()
        case "kazoo": return kazoo()
        case "dialup": return dialup()
        case "chiptune": return chiptune()
        case "chaos": return chaos()
        default: return airhorn()
        }
    }

    // MARK: - Sounds

    /// Three detuned saws a semitone apart, scooping up into pitch: BWAP BWAP BWAAAAAP.
    static func airhorn() -> [Double] {
        var tr = Track(seconds: 2.7)
        let voices = [415.3, 440.0, 466.16, 830.6]
        for (start, length) in [(0.0, 0.2), (0.27, 0.2), (0.54, 1.3)] {
            var phases = [Phasor](repeating: Phasor(), count: voices.count)
            var lp = Biquad.lowpass(4_800)
            var presence = Biquad.bandpass(1_900, q: 0.9)
            tr.add(at: start, duration: length, attack: 0.012, release: 0.05) { t, _ in
                let bend = 1 - 0.07 * exp(-t / 0.03)
                let wobble = 1 + 0.004 * sin(2 * .pi * 5.5 * t)
                var v = 0.0
                for k in voices.indices {
                    let f = voices[k] * bend * wobble
                    v += Wave.saw(phases[k].tick(f), f / sampleRate) * (k == 3 ? 0.5 : 1)
                }
                let driven = tanh(3 * v / 3.5)
                let shaped = lp.process(driven)
                return 0.7 * shaped + 0.7 * presence.process(shaped)
            }
        }
        return tr.samples
    }

    /// Honks: a growling saw pushed through goose-shaped formants, pitch jumping up then sagging.
    static func goose() -> [Double] {
        var tr = Track(seconds: 3.0)
        var rng = RNG(seed: 7)
        let honks: [(Double, Double, Double)] = [
            (0.00, 0.20, 1.00), (0.30, 0.22, 1.05), (0.62, 0.38, 0.95),
            (1.30, 0.14, 1.10), (1.48, 0.14, 1.12), (1.66, 0.14, 1.15),
            (1.84, 0.40, 1.00), (2.45, 0.30, 0.90),
        ]
        for (start, length, pitch) in honks {
            var ph = Phasor()
            var f1 = Biquad.bandpass(1_050, q: 3)
            var f2 = Biquad.bandpass(2_500, q: 5)
            var f3 = Biquad.bandpass(3_600, q: 6)
            tr.add(at: start, duration: length, attack: 0.01, release: 0.05) { t, progress in
                let contour = progress < 0.15 ? 1 + 0.25 * progress / 0.15 : 1.25 - 0.55 * (progress - 0.15) / 0.85
                let f = 430 * pitch * contour * (1 + 0.015 * rng.bipolar())
                let growl = 1 + 0.6 * sin(2 * .pi * 38 * t)
                let source = (Wave.saw(ph.tick(f), f / sampleRate) + 0.25 * rng.bipolar()) * growl
                let v = 1.4 * f1.process(source) + 1.1 * f2.process(source) + 0.7 * f3.process(source) + 0.15 * source
                return tanh(2.5 * v)
            }
        }
        return tr.samples
    }

    /// The old car horn: AH-OOO-GAH, twice.
    static func klaxon() -> [Double] {
        var tr = Track(seconds: 2.6)
        for start in [0.0, 1.3] {
            var ph = Phasor(), ph2 = Phasor()
            var lp = Biquad.lowpass(3_500)
            tr.add(at: start, duration: 1.0, attack: 0.02, release: 0.08) { _, progress in
                let f: Double
                if progress < 0.55 { f = 170 + 420 * pow(progress / 0.55, 0.6) }
                else if progress < 0.8 { f = 590 }
                else { f = 590 - 160 * (progress - 0.8) / 0.2 }
                let v = Wave.square(ph.tick(f), f / sampleRate, duty: 0.4) + 0.4 * Wave.saw(ph2.tick(f * 1.5), f * 1.5 / sampleRate)
                return tanh(2.2 * lp.process(v))
            }
        }
        return tr.samples
    }

    /// The classic digital alarm: four sharp beeps around 2.9 kHz, where ears are most sensitive.
    static func microwave() -> [Double] {
        var tr = Track(seconds: 2.0)
        for group in 0..<2 {
            for beep in 0..<4 {
                var ph = Phasor()
                let f = 2_900.0
                tr.add(at: Double(group) + Double(beep) * 0.13, duration: 0.075, attack: 0.002, release: 0.004) { _, _ in
                    let p = ph.tick(f)
                    return 0.8 * Wave.sine(p) + 0.35 * Wave.square(p, f / sampleRate)
                }
            }
        }
        return tr.samples
    }

    /// A wail, then a yelp, over four-on-the-floor kick and hats.
    static func siren() -> [Double] {
        var tr = Track(seconds: 4.0)
        var ph = Phasor(), ph2 = Phasor()
        tr.add(at: 0, duration: 4.0, attack: 0.02, release: 0.02) { t, _ in
            let f = t < 2 ? 950 + 450 * sin(2 * .pi * 0.5 * t - .pi / 2) : 1_050 + 330 * sin(2 * .pi * 6 * (t - 2))
            let p = ph.tick(f)
            return 0.7 * Wave.tri(p) + 0.25 * Wave.saw(p, f / sampleRate) + 0.15 * Wave.sine(ph2.tick(f * 2))
        }
        for beat in 0..<8 {
            let start = Double(beat) * 0.5
            var kick = Phasor()
            tr.add(at: start, duration: 0.18, gain: 0.9, attack: 0.001, release: 0.03) { t, _ in
                Wave.sine(kick.tick(50 + 110 * exp(-t / 0.03))) * exp(-t / 0.08)
            }
            var hp = Biquad.highpass(7_000)
            var rng = RNG(seed: UInt64(beat + 1))
            tr.add(at: start + 0.25, duration: 0.05, gain: 0.35, attack: 0.001, release: 0.02) { t, _ in
                hp.process(rng.bipolar()) * exp(-t / 0.015)
            }
        }
        return tr.samples
    }

    /// Cock-a-doodle-doo, three times, each one more caffeinated.
    static func rooster() -> [Double] {
        var tr = Track(seconds: 2.6)
        crow(into: &tr, at: 0.0, speed: 1.25, pitch: 1.0, seed: 1)
        crow(into: &tr, at: 0.8, speed: 1.25, pitch: 1.0, seed: 2)
        crow(into: &tr, at: 1.6, speed: 1.45, pitch: 1.12, seed: 3)
        return tr.samples
    }

    private static func crow(into tr: inout Track, at start: Double, speed: Double, pitch: Double, seed: UInt64) {
        // (duration, start pitch, end pitch) for "cock", "a", "doodle", "doooo".
        let syllables: [(Double, Double, Double)] = [(0.09, 720, 780), (0.07, 650, 640), (0.16, 880, 960), (0.5, 1_020, 800)]
        var rng = RNG(seed: seed)
        var cursor = start
        for (length, f0, f1) in syllables {
            let d = length / speed
            var ph = Phasor()
            var b1 = Biquad.bandpass(1_400, q: 2), b2 = Biquad.bandpass(2_800, q: 3), b3 = Biquad.bandpass(4_200, q: 4)
            tr.add(at: cursor, duration: d, attack: 0.008, release: 0.03) { t, progress in
                let f = (f0 + (f1 - f0) * progress) * pitch * (1 + 0.02 * sin(2 * .pi * 9 * t))
                let source = Wave.saw(ph.tick(f), f / sampleRate) + 0.1 * rng.bipolar()
                return tanh(2 * (1.2 * b1.process(source) + b2.process(source) + 0.6 * b3.process(source) + 0.2 * source))
            }
            cursor += d + 0.02 / speed
        }
    }

    /// Random pentatonic bleeps, glitch bursts, then a bitcrusher for that cheap-robot sheen.
    static func robot() -> [Double] {
        var tr = Track(seconds: 3.2)
        var rng = RNG(seed: 42)
        let scale = [0, 3, 5, 7, 10]
        let step = 0.1
        for n in 0..<32 {
            let start = Double(n) * step
            if n % 8 == 7 {
                var noise = RNG(seed: UInt64(n))
                var sweep = Phasor()
                tr.add(at: start, duration: step, gain: 0.8, attack: 0.002, release: 0.01) { _, progress in
                    Wave.sine(sweep.tick(300 + 3_000 * progress)) * (noise.unit() > 0.5 ? 1 : -0.6)
                }
                continue
            }
            let midi = 69 + scale[rng.int(scale.count)] + 12 * rng.int(2)
            let f0 = midiFrequency(midi)
            let glide = rng.bipolar() * 0.3
            var ph = Phasor()
            tr.add(at: start, duration: step * 0.85, attack: 0.002, release: 0.01) { _, progress in
                let f = f0 * (1 + glide * progress)
                return Wave.square(ph.tick(f), f / sampleRate, duty: 0.25)
            }
        }
        var hold = 0.0
        for i in tr.samples.indices {
            if i % 3 == 0 { hold = (tr.samples[i] * 12).rounded() / 12 }
            tr.samples[i] = hold
        }
        return tr.samples
    }

    /// An original fanfare on a very buzzy kazoo.
    static func kazoo() -> [Double] {
        var tr = Track(seconds: 3.5)
        let eighth = 0.17
        let notes: [(Int?, Int)] = [
            (67, 1), (72, 1), (76, 1), (79, 2), (76, 1), (79, 3), (nil, 1),
            (81, 1), (79, 1), (77, 1), (76, 1), (74, 1), (76, 1), (72, 3), (nil, 1),
        ]
        var rng = RNG(seed: 99)
        var cursor = 0.0
        for (midi, beats) in notes {
            let length = Double(beats) * eighth
            defer { cursor += length }
            guard let midi else { continue }
            let target = midiFrequency(midi)
            var ph = Phasor()
            var f1 = Biquad.bandpass(700, q: 3), f2 = Biquad.bandpass(1_250, q: 4), f3 = Biquad.bandpass(2_600, q: 5)
            tr.add(at: cursor, duration: length - 0.012, attack: 0.01, release: 0.03) { t, _ in
                let scoop = pow(2, -0.6 / 12 * exp(-t / 0.04))
                let f = target * scoop * (1 + 0.01 * sin(2 * .pi * 5.5 * t))
                let saw = Wave.saw(ph.tick(f), f / sampleRate)
                let buzz = (saw > 0 ? 1.0 : -1.0) * min(1, abs(saw) * 3) * 0.35 + 0.08 * rng.bipolar()
                let source = saw + buzz
                return tanh(1.8 * (f1.process(source) + 1.2 * f2.process(source) + 0.8 * f3.process(source) + 0.25 * source))
            }
        }
        return tr.samples
    }

    /// Dial tone, a phone number, the answer tone, the handshake, the screech, the hiss.
    static func dialup() -> [Double] {
        var tr = Track(seconds: 4.6)
        tr.add(at: 0, duration: 0.35, gain: 0.7) { t, _ in 0.5 * sin(2 * .pi * 350 * t) + 0.5 * sin(2 * .pi * 440 * t) }

        let pad: [Character: (Double, Double)] = [
            "1": (697, 1_209), "2": (697, 1_336), "3": (697, 1_477), "4": (770, 1_209),
            "5": (770, 1_336), "6": (770, 1_477), "7": (852, 1_209), "8": (852, 1_336), "9": (852, 1_477),
        ]
        for (i, digit) in "5551234".enumerated() {
            guard let (low, high) = pad[digit] else { continue }
            tr.add(at: 0.45 + Double(i) * 0.13, duration: 0.08, attack: 0.003, release: 0.005) { t, _ in
                0.5 * sin(2 * .pi * low * t) + 0.5 * sin(2 * .pi * high * t)
            }
        }
        tr.add(at: 1.40, duration: 0.45, gain: 0.8) { t, _ in sin(2 * .pi * 2_100 * t) }
        tr.add(at: 1.95, duration: 0.5, gain: 0.8) { t, _ in
            let f = Int(t / 0.06) % 2 == 0 ? 1_200.0 : 2_400.0
            return sin(2 * .pi * f * t)
        }
        var screechNoise = RNG(seed: 5)
        var screech = Phasor()
        var band = Biquad.bandpass(2_000, q: 1.2)
        tr.add(at: 2.5, duration: 1.0, attack: 0.01, release: 0.05) { t, _ in
            let f = 1_800 + 600 * sin(2 * .pi * 13 * t) + 300 * sin(2 * .pi * 3 * t)
            return tanh(2 * (Wave.saw(screech.tick(f), f / sampleRate) + band.process(0.6 * screechNoise.bipolar())))
        }
        var fsk = Phasor()
        var bits = RNG(seed: 11)
        var bit = false
        tr.add(at: 3.5, duration: 0.6, gain: 0.8) { t, _ in
            if Int(t * sampleRate) % 147 == 0 { bit = bits.unit() > 0.5 }
            return Wave.sine(fsk.tick(bit ? 1_180 : 980))
        }
        var hiss = RNG(seed: 13)
        var hp = Biquad.highpass(2_000)
        tr.add(at: 4.1, duration: 0.5, gain: 0.7) { t, _ in hp.process(hiss.bipolar()) * exp(-t / 0.3) }
        return tr.samples
    }

    /// Fast pulse-wave arpeggios with a triangle bass and noise snare.
    static func chiptune() -> [Double] {
        var tr = Track(seconds: 3.2)
        let roots = [60, 56, 58, 60]
        let pattern = [0, 4, 7, 12, 7, 4]
        for (c, root) in roots.enumerated() {
            let chordStart = Double(c) * 0.8
            for n in 0..<16 {
                let midi = root + 12 + pattern[n % pattern.count] + (c == 3 && n > 8 ? 12 : 0)
                let f = midiFrequency(midi)
                var ph = Phasor()
                tr.add(at: chordStart + Double(n) * 0.05, duration: 0.045, gain: 0.6, attack: 0.001, release: 0.005) { _, _ in
                    Wave.square(ph.tick(f), f / sampleRate, duty: 0.125)
                }
            }
            for b in 0..<4 {
                let f = midiFrequency(root - 12)
                var ph = Phasor()
                tr.add(at: chordStart + Double(b) * 0.2, duration: 0.15, gain: 0.7, attack: 0.002, release: 0.02) { _, _ in
                    Wave.tri(ph.tick(f))
                }
            }
            var noise = RNG(seed: UInt64(c + 20))
            var hp = Biquad.highpass(1_500)
            tr.add(at: chordStart + 0.4, duration: 0.08, gain: 0.5, attack: 0.001, release: 0.03) { t, _ in
                hp.process(noise.bipolar()) * exp(-t / 0.03)
            }
        }
        return tr.samples
    }

    /// Everything, back to back, each at its own full volume.
    static func chaos() -> [Double] {
        let order = ["airhorn", "goose", "microwave", "klaxon", "rooster", "robot", "siren", "kazoo", "dialup", "chiptune"]
        var out: [Double] = []
        for id in order {
            var part = raw(id)
            let peak = part.reduce(0) { max($0, abs($1)) }
            if peak > 0 { part = part.map { $0 / peak } }
            out += part
            out += [Double](repeating: 0, count: Int(0.15 * sampleRate))
        }
        return out
    }

    // MARK: - Mastering

    /// Removes rumble, normalises, saturates for loudness and smooths the loop seam.
    static func master(_ input: [Double]) -> [Float] {
        guard !input.isEmpty else { return [] }
        var hp = Biquad.highpass(60)
        var y = input.map { hp.process($0) }
        let peak = y.reduce(0) { max($0, abs($1)) }
        if peak > 0 { y = y.map { $0 / peak } }
        let drive = 1.8, norm = tanh(drive)
        y = y.map { tanh(drive * $0) / norm }
        let fade = min(Int(0.004 * sampleRate), y.count / 2)
        for i in 0..<fade {
            let g = Double(i) / Double(fade)
            y[i] *= g
            y[y.count - 1 - i] *= g
        }
        return y.map { Float($0 * 0.97) }
    }

    public struct Stats: Sendable {
        public var seconds: Double
        public var peak: Double
        public var rmsDB: Double
    }

    public static func stats(_ samples: [Float]) -> Stats {
        let peak = samples.reduce(Float(0)) { max($0, abs($1)) }
        let mean = samples.reduce(0.0) { $0 + Double($1) * Double($1) } / Double(max(samples.count, 1))
        return Stats(seconds: Double(samples.count) / sampleRate, peak: Double(peak), rmsDB: 10 * log10(max(mean, 1e-12)))
    }

    /// 16-bit mono WAV, for previews and the command-line tool.
    public static func wav(_ samples: [Float]) -> Data {
        var data = Data()
        func put<T: FixedWidthInteger>(_ v: T) { withUnsafeBytes(of: v.littleEndian) { data.append(contentsOf: $0) } }
        let rate = UInt32(sampleRate)
        let bytes = UInt32(samples.count * 2)
        data.append(contentsOf: Array("RIFF".utf8)); put(UInt32(36) + bytes)
        data.append(contentsOf: Array("WAVE".utf8))
        data.append(contentsOf: Array("fmt ".utf8)); put(UInt32(16)); put(UInt16(1)); put(UInt16(1))
        put(rate); put(rate * 2); put(UInt16(2)); put(UInt16(16))
        data.append(contentsOf: Array("data".utf8)); put(bytes)
        for s in samples { put(Int16(max(-1, min(1, s)) * 32_767)) }
        return data
    }

    static func midiFrequency(_ note: Int) -> Double {
        440 * pow(2, Double(note - 69) / 12)
    }
}

// MARK: - DSP building blocks

struct Track {
    var samples: [Double]

    init(seconds: Double) {
        samples = [Double](repeating: 0, count: Int(seconds * SoundSynth.sampleRate))
    }

    /// Adds a generated segment at `start` seconds. `generate` gets local time and progress (0…1).
    mutating func add(
        at start: Double,
        duration: Double,
        gain: Double = 1,
        attack: Double = 0.005,
        release: Double = 0.02,
        _ generate: (Double, Double) -> Double
    ) {
        let sr = SoundSynth.sampleRate
        let first = Int(start * sr)
        let count = Int(duration * sr)
        for k in 0..<count {
            let i = first + k
            guard i < samples.count else { break }
            let t = Double(k) / sr
            var env = t < attack ? t / attack : 1
            let remaining = duration - t
            if remaining < release { env = min(env, remaining / release) }
            samples[i] += gain * env * generate(t, t / duration)
        }
    }
}

struct Phasor {
    var phase = 0.0

    /// Advances by one sample at frequency `f` and returns the phase before the step (0…1).
    mutating func tick(_ f: Double) -> Double {
        let p = phase
        phase += f / SoundSynth.sampleRate
        phase -= floor(phase)
        return p
    }
}

enum Wave {
    static func sine(_ p: Double) -> Double { sin(2 * .pi * p) }
    static func tri(_ p: Double) -> Double { 4 * abs(p - 0.5) - 1 }

    /// Band-limited saw (PolyBLEP) so high notes don't fizz with aliasing.
    static func saw(_ p: Double, _ dt: Double) -> Double { 2 * p - 1 - blep(p, dt) }

    static func square(_ p: Double, _ dt: Double, duty: Double = 0.5) -> Double {
        var v = p < duty ? 1.0 : -1.0
        v += blep(p, dt)
        v -= blep((p - duty + 1).truncatingRemainder(dividingBy: 1), dt)
        return v
    }

    static func blep(_ t: Double, _ dt: Double) -> Double {
        guard dt > 0 else { return 0 }
        if t < dt { let x = t / dt; return x + x - x * x - 1 }
        if t > 1 - dt { let x = (t - 1) / dt; return x * x + x + x + 1 }
        return 0
    }
}

/// RBJ cookbook biquad.
struct Biquad {
    var b0 = 1.0, b1 = 0.0, b2 = 0.0, a1 = 0.0, a2 = 0.0
    var x1 = 0.0, x2 = 0.0, y1 = 0.0, y2 = 0.0

    static func lowpass(_ f: Double, q: Double = 0.707) -> Biquad {
        let (cosw, alpha) = terms(f, q)
        return Biquad(a0: 1 + alpha, b0: (1 - cosw) / 2, b1: 1 - cosw, b2: (1 - cosw) / 2, a1: -2 * cosw, a2: 1 - alpha)
    }

    static func highpass(_ f: Double, q: Double = 0.707) -> Biquad {
        let (cosw, alpha) = terms(f, q)
        return Biquad(a0: 1 + alpha, b0: (1 + cosw) / 2, b1: -(1 + cosw), b2: (1 + cosw) / 2, a1: -2 * cosw, a2: 1 - alpha)
    }

    /// Band-pass with 0 dB peak gain.
    static func bandpass(_ f: Double, q: Double) -> Biquad {
        let (cosw, alpha) = terms(f, q)
        return Biquad(a0: 1 + alpha, b0: alpha, b1: 0, b2: -alpha, a1: -2 * cosw, a2: 1 - alpha)
    }

    private static func terms(_ f: Double, _ q: Double) -> (Double, Double) {
        let w0 = 2 * .pi * f / SoundSynth.sampleRate
        return (cos(w0), sin(w0) / (2 * q))
    }

    private init(a0: Double, b0: Double, b1: Double, b2: Double, a1: Double, a2: Double) {
        self.b0 = b0 / a0
        self.b1 = b1 / a0
        self.b2 = b2 / a0
        self.a1 = a1 / a0
        self.a2 = a2 / a0
    }

    mutating func process(_ x: Double) -> Double {
        let y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2
        x2 = x1; x1 = x
        y2 = y1; y1 = y
        return y
    }
}

/// SplitMix64: tiny, deterministic, so every build sounds identical.
struct RNG {
    var state: UInt64

    init(seed: UInt64) { state = seed &+ 0x9E37_79B9_7F4A_7C15 }

    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }

    mutating func unit() -> Double { Double(next() >> 11) / Double(1 << 53) }
    mutating func bipolar() -> Double { unit() * 2 - 1 }
    mutating func int(_ n: Int) -> Int { Int(next() % UInt64(max(n, 1))) }
}
