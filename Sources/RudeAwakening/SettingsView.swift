import AlarmCore
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Which Settings tab is showing, so other parts of the app can open a specific one.
@MainActor
final class SettingsRouter: ObservableObject {
    static let shared = SettingsRouter()
    enum Tab: String { case brain, noise, rules, general }
    @Published var tab = Tab.brain
}

struct SettingsView: View {
    @ObservedObject private var router = SettingsRouter.shared

    var body: some View {
        TabView(selection: $router.tab) {
            BrainSettings().tabItem { Label("Brain", systemImage: "brain.head.profile") }.tag(SettingsRouter.Tab.brain)
            NoiseSettings().tabItem { Label("Noise", systemImage: "speaker.wave.3.fill") }.tag(SettingsRouter.Tab.noise)
            RulesSettings().tabItem { Label("Wake-up rules", systemImage: "alarm") }.tag(SettingsRouter.Tab.rules)
            GeneralSettings().tabItem { Label("General", systemImage: "gearshape") }.tag(SettingsRouter.Tab.general)
        }
        .padding(16)
        .frame(minWidth: 560, minHeight: 480)
    }
}

/// Paste a key, test it, save it. Shared by Settings and the first-run sheet.
struct KeyEntry: View {
    var onSaved: () -> Void = {}
    @State private var draft = ""
    @State private var status: Status = .idle
    @State private var hasKey = KeyStore.hasKey

    enum Status: Equatable {
        case idle, testing, ok(String), failed(String)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SecureField("OpenRouter key", text: $draft, prompt: Text("Starts with sk-or-v1-…"))
                    .labelsHidden()
                    .textFieldStyle(.roundedBorder)
                    .font(.body.monospaced())
                    .onSubmit(save)
                Button("Save & test", action: save)
                    .buttonStyle(.borderedProminent)
                    .tint(Theme.hot)
                    .disabled(draft.trimmed.isEmpty || status == .testing)
                    .keyboardShortcut(.defaultAction)
            }
            switch status {
            case .idle:
                if hasKey {
                    Label("Key saved. I'm smart now.", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                }
            case .testing:
                HStack(spacing: 6) { ProgressView().controlSize(.small); Text("Poking OpenRouter…") }
            case .ok(let message):
                Label(message, systemImage: "checkmark.seal.fill").foregroundStyle(.green)
            case .failed(let message):
                Label(message, systemImage: "xmark.octagon.fill").foregroundStyle(.red)
            }
        }
        .font(.callout)
    }

    private func save() {
        let key = draft.trimmed
        guard !key.isEmpty else { return }
        status = .testing
        Task {
            do {
                let info = try await OpenRouterClient.check(key: key)
                try KeyStore.save(key)
                hasKey = true
                draft = ""
                var message = "Key works and is saved. I'm smart now."
                if let remaining = info.limitRemaining { message += String(format: " ($%.2f left on it.)", remaining) }
                status = .ok(message)
                onSaved()
            } catch {
                status = .failed((error as? LocalizedError)?.errorDescription ?? error.localizedDescription)
            }
        }
    }
}

struct BrainSettings: View {
    @EnvironmentObject private var prefs: Prefs
    @State private var hasKey = KeyStore.hasKey
    @State private var customModel = ""

    private var isSuggested: Bool { OpenRouterClient.suggestedModels.contains { $0.id == prefs.model } }

    var body: some View {
        Form {
            Section {
                KeyEntry { hasKey = true }
                HStack {
                    Link("Get a key at openrouter.ai/keys", destination: OpenRouterClient.keysPage)
                    Spacer()
                    if hasKey {
                        Button("Remove key", role: .destructive) {
                            KeyStore.remove()
                            hasKey = false
                        }
                    }
                }
            } header: {
                Text("OpenRouter key")
            } footer: {
                Text("Your key stays on this Mac, in a file only you can read, and is only ever sent to openrouter.ai. Each sentence costs a tiny fraction of a cent. Without a key, a small offline parser handles simple things like “in 20 min” and “tomorrow at 7”.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }

            Section("Model") {
                Picker("Model", selection: Binding(
                    get: { isSuggested ? prefs.model : "custom" },
                    set: { if $0 != "custom" { prefs.model = $0 } else { customModel = prefs.model } }
                )) {
                    ForEach(OpenRouterClient.suggestedModels, id: \.id) { Text($0.name).tag($0.id) }
                    Text("Other OpenRouter model…").tag("custom")
                }
                if !isSuggested {
                    TextField("Model id", text: Binding(get: { prefs.model }, set: { prefs.model = $0.trimmed }), prompt: Text("provider/model-name"))
                        .font(.body.monospaced())
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct NoiseSettings: View {
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var player: AlarmPlayer
    @EnvironmentObject private var store: AlarmStore
    @State private var customSounds: [String] = []

    var body: some View {
        Form {
            Section("Default sound") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 230), spacing: 10)], spacing: 10) {
                    ForEach(SoundLibrary.all) { sound in
                        SoundTile(id: sound.id, emoji: sound.emoji, name: sound.name, blurb: sound.blurb)
                    }
                    ForEach(customSounds, id: \.self) { name in
                        SoundTile(id: "file:\(name)", emoji: "🎵", name: name, blurb: "Your own noise.")
                    }
                }
                HStack {
                    Button("Add your own sound…", systemImage: "plus", action: addSound)
                    Spacer()
                    Button("Test the full alarm", systemImage: "alarm.waves.left.and.right") {
                        store.testRing(soundID: prefs.defaultSound)
                    }
                }
            }

            Section {
                Toggle("Crank the Mac's volume when an alarm rings", isOn: $prefs.crankVolume)
                if prefs.crankVolume {
                    LabeledContent("Crank it to") {
                        HStack {
                            Slider(value: $prefs.crankLevel, in: 0.5...1, step: 0.05)
                            Text("\(Int(prefs.crankLevel * 100))%").monospacedDigit().frame(width: 44, alignment: .trailing)
                        }
                    }
                    Toggle("Volume lock: if you turn me down, I turn myself back up", isOn: $prefs.volumeLock)
                }
                Toggle("Yell what the alarm is for, out loud", isOn: $prefs.voiceNag)
            } header: {
                Text("Loudness")
            } footer: {
                Text("Your previous volume comes back when the alarm stops. Plays through whatever is connected, headphones included.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
        }
        .formStyle(.grouped)
        .onAppear(perform: refresh)
    }

    private func refresh() {
        customSounds = (try? FileManager.default.contentsOfDirectory(atPath: AppPaths.sounds.path))?
            .filter { !$0.hasPrefix(".") }.sorted() ?? []
    }

    private func addSound() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.audio]
        panel.allowsMultipleSelection = false
        panel.message = "Pick something loud."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let target = AppPaths.sounds.appendingPathComponent(url.lastPathComponent)
        try? FileManager.default.removeItem(at: target)
        try? FileManager.default.copyItem(at: url, to: target)
        prefs.defaultSound = "file:\(url.lastPathComponent)"
        refresh()
    }
}

struct SoundTile: View {
    let id: String
    let emoji: String
    let name: String
    let blurb: String
    @EnvironmentObject private var prefs: Prefs
    @EnvironmentObject private var player: AlarmPlayer

    var body: some View {
        let selected = prefs.defaultSound == id
        HStack(spacing: 10) {
            Text(emoji).font(.system(size: 28)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(name).font(.headline)
                Text(blurb).font(.caption).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            Button {
                player.togglePreview(id)
            } label: {
                Image(systemName: player.previewing == id ? "stop.circle.fill" : "play.circle.fill").font(.title2)
            }
            .buttonStyle(.borderless)
            .help("Preview (politely, at the current volume)")
            .accessibilityLabel(player.previewing == id ? "Stop preview of \(name)" : "Preview \(name)")
        }
        .padding(10)
        .background(selected ? AnyShapeStyle(Theme.hot.opacity(0.12)) : AnyShapeStyle(.quaternary.opacity(0.4)), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(selected ? Theme.hot : .clear, lineWidth: 2))
        .contentShape(Rectangle())
        .onTapGesture { prefs.defaultSound = id }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

struct RulesSettings: View {
    @EnvironmentObject private var prefs: Prefs

    var body: some View {
        Form {
            Section("Snooze") {
                Picker("Snooze for", selection: $prefs.snoozeMinutes) {
                    ForEach([3, 5, 9, 10, 15, 20], id: \.self) { Text("\($0) minutes\($0 == 9 ? " (classic)" : "")").tag($0) }
                }
            }
            Section {
                Picker("Prove you're awake", selection: $prefs.challenge) {
                    ForEach(Challenge.allCases) { Text($0.label).tag($0) }
                }
            } footer: {
                Text("With maths on, the stop button only appears once you've solved a sum. Snooze always works.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }
            Section("Giving up") {
                Picker("Stop ringing after", selection: $prefs.autoStopMinutes) {
                    ForEach([5, 10, 15, 30, 60], id: \.self) { Text("\($0) minutes").tag($0) }
                    Text("Never. I am relentless.").tag(0)
                }
            }
        }
        .formStyle(.grouped)
    }
}

struct GeneralSettings: View {
    @EnvironmentObject private var prefs: Prefs
    @State private var launchAtLogin = LaunchAtLogin.isEnabled
    @State private var loginError: String?

    var body: some View {
        Form {
            Section {
                Toggle("Open at login", isOn: Binding(get: { launchAtLogin }, set: setLogin))
                if LaunchAtLogin.needsApproval {
                    Button("Approve in System Settings › Login Items") { LaunchAtLogin.openSystemSettings() }
                }
                if let loginError { Text(loginError).foregroundStyle(.red).font(.caption) }
                Toggle("Keep the Mac awake while alarms are set", isOn: $prefs.keepAwake)
            } header: {
                Text("Reliability")
            } footer: {
                Text("Alarms only ring while Rude Awakening is running and the Mac is awake. Keeping it awake stops idle sleep (the screen can still turn off). Closing the lid still sleeps the Mac, and an alarm missed while asleep shows up when it wakes.")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
            }

            Section("Shortcuts and looks") {
                Picker("Quick alarm from anywhere", selection: $prefs.hotKey) {
                    ForEach(HotKeyChoice.allCases) { Text($0.label).tag($0) }
                }
                Toggle("Show the countdown in the menu bar", isOn: $prefs.showCountdown)
                Toggle("Show in the Dock", isOn: $prefs.showDockIcon)
                Toggle("Open the window when the app starts", isOn: $prefs.openWindowAtLaunch)
            }

            Section("About") {
                LabeledContent("Version", value: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")
                LabeledContent("Data folder") {
                    Button("Show in Finder") { NSWorkspace.shared.activateFileViewerSelecting([AppPaths.support]) }
                }
                Link("Source code on GitHub", destination: URL(string: "https://github.com/adoistic/rude-awakening")!)
            }
        }
        .formStyle(.grouped)
    }

    private func setLogin(_ on: Bool) {
        do {
            try LaunchAtLogin.set(on)
            loginError = nil
        } catch {
            loginError = "macOS said no: \(error.localizedDescription)"
        }
        launchAtLogin = LaunchAtLogin.isEnabled
    }
}
