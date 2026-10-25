import AVFoundation
import AlarmCore
import AudioToolbox
import CoreAudio

/// Plays alarms through the Mac's speakers, cranks the system volume, fights back when
/// you turn it down, and yells the alarm's reason out loud between blasts.
@MainActor
final class AlarmPlayer: NSObject, ObservableObject, AVSpeechSynthesizerDelegate {
    static let shared = AlarmPlayer()

    /// The sound being previewed in Settings, if any.
    @Published private(set) var previewing: String?

    private let engine = AVAudioEngine()
    private let node = AVAudioPlayerNode()
    private let speech = AVSpeechSynthesizer()
    private static var cache: [String: [Float]] = [:]

    private var currentSound: String?
    private var isAlarm = false
    private var restoreVolume: Float?
    private var restoreMuted: Bool?
    private var lockTarget: Float?
    private var lastFight = Date.distantPast
    private var onVolumeFight: (() -> Void)?
    private var lines: [String] = []
    private var lineIndex = 0
    private var timers: [Timer] = []
    private var previewTimer: Timer?
    /// RUDE_AWAKENING_SILENT=1: the whole ringing flow, minus sound, speech and volume changes. For testing.
    private let silent = ProcessInfo.processInfo.environment["RUDE_AWAKENING_SILENT"] == "1" || Automation.isOn

    private override init() {
        super.init()
        engine.attach(node)
        speech.delegate = self
        NotificationCenter.default.addObserver(forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main) { _ in
            // Headphones plugged in or out: the engine stops, so start the loop again.
            MainActor.assumeIsolated {
                let player = AlarmPlayer.shared
                if let sound = player.currentSound, player.isAlarm { _ = player.play(sound, volume: 1) }
            }
        }
    }

    /// Renders every built-in sound in the background so the first ring starts instantly.
    static func prewarm() {
        Task.detached(priority: .utility) {
            for info in SoundLibrary.all where info.id != "chaos" {
                let samples = SoundSynth.render(info.id)
                await MainActor.run { cache[info.id] = samples }
            }
        }
    }

    // MARK: Alarm

    func startAlarm(soundID: String, crankTo: Float?, lockVolume: Bool, voiceLines: [String], onVolumeFight: @escaping () -> Void) {
        stopPreview()
        stopTimers()
        isAlarm = true
        self.onVolumeFight = onVolumeFight

        if let target = crankTo, !silent {
            restoreVolume = SystemVolume.volume
            restoreMuted = SystemVolume.isMuted
            _ = SystemVolume.setMuted(false)
            _ = SystemVolume.setVolume(target)
            if lockVolume {
                lockTarget = target
                schedule(every: 0.4) { AlarmPlayer.shared.enforceVolume() }
            }
        }

        _ = play(soundID, volume: 1)

        lines = silent ? [] : voiceLines
        lineIndex = 0
        if !lines.isEmpty {
            schedule(after: 2.5) { AlarmPlayer.shared.speakNext() }
            schedule(every: 10) { AlarmPlayer.shared.speakNext() }
        }
    }

    func stopAlarm() {
        isAlarm = false
        stopTimers()
        speech.stopSpeaking(at: .immediate)
        node.stop()
        engine.stop()
        currentSound = nil
        lockTarget = nil
        if let v = restoreVolume { _ = SystemVolume.setVolume(v) }
        if let m = restoreMuted { _ = SystemVolume.setMuted(m) }
        restoreVolume = nil
        restoreMuted = nil
    }

    private func enforceVolume() {
        guard let target = lockTarget else { return }
        let muted = SystemVolume.isMuted ?? false
        let level = SystemVolume.volume ?? target
        guard muted || level < target - 0.02 else { return }
        _ = SystemVolume.setMuted(false)
        _ = SystemVolume.setVolume(target)
        // One fight per gesture, not one per key repeat.
        if Date().timeIntervalSince(lastFight) > 1.5 {
            lastFight = Date()
            onVolumeFight?()
        }
    }

    private func speakNext() {
        guard isAlarm, !lines.isEmpty, !speech.isSpeaking else { return }
        let utterance = AVSpeechUtterance(string: lines[lineIndex % lines.count])
        utterance.rate = 0.52
        utterance.pitchMultiplier = 1.15
        utterance.volume = 1
        lineIndex += 1
        node.volume = 0.3 // duck the noise so the words land
        speech.speak(utterance)
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        Task { @MainActor in AlarmPlayer.shared.unduck() }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        Task { @MainActor in AlarmPlayer.shared.unduck() }
    }

    private func unduck() {
        node.volume = silent ? 0 : 1
    }

    // MARK: Preview (polite: no volume cranking)

    func togglePreview(_ soundID: String) {
        if previewing == soundID { stopPreview(); return }
        guard !isAlarm else { return }
        stopPreview()
        guard play(soundID, volume: 0.7) else { return }
        previewing = soundID
        previewTimer = Timer.scheduledTimer(withTimeInterval: soundID == "chaos" ? 10 : 4, repeats: false) { _ in
            MainActor.assumeIsolated { AlarmPlayer.shared.stopPreview() }
        }
    }

    func stopPreview() {
        previewTimer?.invalidate()
        previewTimer = nil
        guard previewing != nil else { return }
        previewing = nil
        if !isAlarm {
            node.stop()
            engine.stop()
            currentSound = nil
        }
    }

    // MARK: Engine

    private func play(_ soundID: String, volume: Float) -> Bool {
        guard let buffer = buffer(for: soundID) ?? buffer(for: SoundLibrary.defaultID) else { return false }
        node.stop()
        engine.stop()
        engine.disconnectNodeOutput(node)
        engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
        engine.mainMixerNode.outputVolume = 1
        do {
            engine.prepare()
            try engine.start()
        } catch {
            NSLog("Rude Awakening: audio engine failed to start: \(error)")
            return false
        }
        node.volume = silent ? 0 : volume
        node.scheduleBuffer(buffer, at: nil, options: .loops)
        node.play()
        currentSound = soundID
        return true
    }

    private func buffer(for soundID: String) -> AVAudioPCMBuffer? {
        if soundID.hasPrefix("file:") { return fileBuffer(String(soundID.dropFirst(5))) }
        let samples: [Float]
        if let cached = Self.cache[soundID] {
            samples = cached
        } else {
            samples = SoundSynth.render(soundID)
            Self.cache[soundID] = samples
        }
        guard !samples.isEmpty,
              let format = AVAudioFormat(standardFormatWithSampleRate: SoundSynth.sampleRate, channels: 2),
              let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(samples.count)),
              let channels = buffer.floatChannelData else { return nil }
        buffer.frameLength = buffer.frameCapacity
        samples.withUnsafeBufferPointer { src in
            for ch in 0..<2 { channels[ch].update(from: src.baseAddress!, count: samples.count) }
        }
        return buffer
    }

    /// A custom sound file, capped at three minutes so a whole album doesn't land in memory.
    private func fileBuffer(_ name: String) -> AVAudioPCMBuffer? {
        let url = AppPaths.sounds.appendingPathComponent(name)
        guard let file = try? AVAudioFile(forReading: url) else { return nil }
        let frames = AVAudioFrameCount(min(file.length, AVAudioFramePosition(file.processingFormat.sampleRate * 180)))
        guard frames > 0, let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: frames) else { return nil }
        do { try file.read(into: buffer, frameCount: frames) } catch { return nil }
        return buffer
    }

    // MARK: Timers

    private func schedule(every interval: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        let t = Timer(timeInterval: interval, repeats: true) { _ in MainActor.assumeIsolated { block() } }
        RunLoop.main.add(t, forMode: .common)
        timers.append(t)
    }

    private func schedule(after delay: TimeInterval, _ block: @escaping @MainActor () -> Void) {
        let t = Timer(timeInterval: delay, repeats: false) { _ in MainActor.assumeIsolated { block() } }
        RunLoop.main.add(t, forMode: .common)
        timers.append(t)
    }

    private func stopTimers() {
        timers.forEach { $0.invalidate() }
        timers.removeAll()
    }
}

/// The Mac's output volume, via Core Audio.
enum SystemVolume {
    private static func outputDevice() -> AudioDeviceID? {
        var id = AudioDeviceID(0)
        var size = UInt32(MemoryLayout<AudioDeviceID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        let status = AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &id)
        return status == noErr && id != 0 ? id : nil
    }

    private static func address(_ selector: AudioObjectPropertySelector) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: kAudioDevicePropertyScopeOutput, mElement: kAudioObjectPropertyElementMain)
    }

    static var volume: Float? {
        guard let device = outputDevice() else { return nil }
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value = Float32(0)
        var size = UInt32(MemoryLayout<Float32>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr ? value : nil
    }

    static func setVolume(_ level: Float) -> Bool {
        guard let device = outputDevice() else { return false }
        var addr = address(kAudioHardwareServiceDeviceProperty_VirtualMainVolume)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return false }
        var value = Float32(min(max(level, 0), 1))
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &value) == noErr
    }

    static var isMuted: Bool? {
        guard let device = outputDevice() else { return nil }
        var addr = address(kAudioDevicePropertyMute)
        guard AudioObjectHasProperty(device, &addr) else { return nil }
        var value = UInt32(0)
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr ? value != 0 : nil
    }

    static func setMuted(_ muted: Bool) -> Bool {
        guard let device = outputDevice() else { return false }
        var addr = address(kAudioDevicePropertyMute)
        var settable: DarwinBoolean = false
        guard AudioObjectHasProperty(device, &addr),
              AudioObjectIsPropertySettable(device, &addr, &settable) == noErr, settable.boolValue else { return false }
        var value = UInt32(muted ? 1 : 0)
        return AudioObjectSetPropertyData(device, &addr, 0, nil, UInt32(MemoryLayout<UInt32>.size), &value) == noErr
    }
}
