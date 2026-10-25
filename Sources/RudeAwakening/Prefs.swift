import AlarmCore
import AppKit
import Carbon.HIToolbox

enum Challenge: String, CaseIterable, Identifiable {
    case off, easy, hard
    var id: String { rawValue }
    var label: String {
        switch self {
        case .off: return "Off: just hold the stop button"
        case .easy: return "Easy maths (23 + 48)"
        case .hard: return "Hard maths (17 × 6 + 29)"
        }
    }
}

enum HotKeyChoice: String, CaseIterable, Identifiable {
    case optionCommandA, controlOptionCommandA, optionCommandY, off
    var id: String { rawValue }

    var label: String {
        switch self {
        case .optionCommandA: return "⌥⌘A"
        case .controlOptionCommandA: return "⌃⌥⌘A"
        case .optionCommandY: return "⌥⌘Y"
        case .off: return "Off"
        }
    }

    /// Carbon key code and modifiers.
    var carbon: (UInt32, UInt32)? {
        switch self {
        case .optionCommandA: return (UInt32(kVK_ANSI_A), UInt32(cmdKey | optionKey))
        case .controlOptionCommandA: return (UInt32(kVK_ANSI_A), UInt32(cmdKey | optionKey | controlKey))
        case .optionCommandY: return (UInt32(kVK_ANSI_Y), UInt32(cmdKey | optionKey))
        case .off: return nil
        }
    }
}

/// User settings, saved in UserDefaults as they change.
@MainActor
final class Prefs: ObservableObject {
    static let shared = Prefs()
    // The test harness gets its own settings so it never touches yours.
    private let d = Automation.isOn ? UserDefaults(suiteName: "com.thothica.RudeAwakening.automation")! : UserDefaults.standard

    @Published var model: String { didSet { d.set(model, forKey: "model") } }
    @Published var defaultSound: String { didSet { d.set(defaultSound, forKey: "defaultSound") } }
    @Published var crankVolume: Bool { didSet { d.set(crankVolume, forKey: "crankVolume") } }
    @Published var crankLevel: Double { didSet { d.set(crankLevel, forKey: "crankLevel") } }
    @Published var volumeLock: Bool { didSet { d.set(volumeLock, forKey: "volumeLock") } }
    @Published var voiceNag: Bool { didSet { d.set(voiceNag, forKey: "voiceNag") } }
    @Published var snoozeMinutes: Int { didSet { d.set(snoozeMinutes, forKey: "snoozeMinutes") } }
    @Published var autoStopMinutes: Int { didSet { d.set(autoStopMinutes, forKey: "autoStopMinutes") } }
    @Published var challenge: Challenge { didSet { d.set(challenge.rawValue, forKey: "challenge") } }
    @Published var keepAwake: Bool { didSet { d.set(keepAwake, forKey: "keepAwake") } }
    @Published var showDockIcon: Bool { didSet { d.set(showDockIcon, forKey: "showDockIcon"); applyDockIcon() } }
    @Published var showCountdown: Bool { didSet { d.set(showCountdown, forKey: "showCountdown") } }
    @Published var openWindowAtLaunch: Bool { didSet { d.set(openWindowAtLaunch, forKey: "openWindowAtLaunch") } }
    @Published var skippedOnboarding: Bool { didSet { d.set(skippedOnboarding, forKey: "skippedOnboarding") } }
    @Published var hotKey: HotKeyChoice {
        didSet {
            d.set(hotKey.rawValue, forKey: "hotKey")
            HotKeyCenter.shared.apply(hotKey)
        }
    }

    private init() {
        d.register(defaults: [
            "model": OpenRouterClient.defaultModel,
            "defaultSound": SoundLibrary.defaultID,
            "crankVolume": true,
            "crankLevel": 1.0,
            "volumeLock": true,
            "voiceNag": true,
            "snoozeMinutes": 9,
            "autoStopMinutes": 15,
            "challenge": Challenge.off.rawValue,
            "keepAwake": true,
            "showDockIcon": true,
            "showCountdown": true,
            "openWindowAtLaunch": true,
            "skippedOnboarding": false,
            "hotKey": HotKeyChoice.optionCommandA.rawValue,
        ])
        model = d.string(forKey: "model") ?? OpenRouterClient.defaultModel
        defaultSound = d.string(forKey: "defaultSound") ?? SoundLibrary.defaultID
        crankVolume = d.bool(forKey: "crankVolume")
        crankLevel = d.double(forKey: "crankLevel")
        volumeLock = d.bool(forKey: "volumeLock")
        voiceNag = d.bool(forKey: "voiceNag")
        snoozeMinutes = d.integer(forKey: "snoozeMinutes")
        autoStopMinutes = d.integer(forKey: "autoStopMinutes")
        challenge = Challenge(rawValue: d.string(forKey: "challenge") ?? "") ?? .off
        keepAwake = d.bool(forKey: "keepAwake")
        showDockIcon = d.bool(forKey: "showDockIcon")
        showCountdown = d.bool(forKey: "showCountdown")
        openWindowAtLaunch = d.bool(forKey: "openWindowAtLaunch")
        skippedOnboarding = d.bool(forKey: "skippedOnboarding")
        hotKey = HotKeyChoice(rawValue: d.string(forKey: "hotKey") ?? "") ?? .optionCommandA
    }

    func applyDockIcon() {
        if Automation.isOn {
            NSApp.setActivationPolicy(.accessory)
            return
        }
        NSApp.setActivationPolicy(showDockIcon ? .regular : .accessory)
        NSApp.activate(ignoringOtherApps: true)
    }
}

/// A system-wide shortcut that opens the quick "yell" box from any app.
/// Uses Carbon's RegisterEventHotKey, which needs no Accessibility permission.
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    var onPress: (() -> Void)?
    private var ref: EventHotKeyRef?
    private var handlerInstalled = false

    func apply(_ choice: HotKeyChoice) {
        if let ref { UnregisterEventHotKey(ref) }
        ref = nil
        guard let (code, modifiers) = choice.carbon else { return }
        installHandler()
        let id = EventHotKeyID(signature: OSType(0x5255_4445), id: 1) // "RUDE"
        RegisterEventHotKey(code, modifiers, id, GetApplicationEventTarget(), 0, &ref)
    }

    private func installHandler() {
        guard !handlerInstalled else { return }
        handlerInstalled = true
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, _ in
            DispatchQueue.main.async { MainActor.assumeIsolated { HotKeyCenter.shared.onPress?() } }
            return noErr
        }, 1, &spec, nil, nil)
    }
}
