import AlarmCore
import AppKit
import SwiftUI

/// A test harness for driving the real app without a mouse or Xcode's UI testing.
///
///   RUDE_AWAKENING_AUTOMATION=/tmp/rude open "dist/Rude Awakening.app"
///
/// In this mode the app is silent, keeps its windows off-screen, never takes focus, and uses
/// /tmp/rude/support and its own settings instead of yours. It runs the lines appended to
/// /tmp/rude/commands.txt one at a time and writes what happened to /tmp/rude/log.txt:
///
///   say every weekday at 7:15 for gym    type a sentence, log the reply and the alarms it made
///   show main | quick | brain | noise | rules | general   open a window or a Settings tab
///   snap <name> main|settings|quick|ring|menubar|onboarding|sheet   save that window as <name>.png
///   edit-new | edit-close               open or close the "add by hand" sheet
///   ring                                  ring the default sound as a test
///   snooze | stop                        act on the ringing alarm
///   pref <key> <value>                   change a setting (challenge hard, voiceNag false…)
///   alarms                               log every alarm and when it rings next
///   wait <seconds>                       pause
///   quit                                 quit without the "are you sure" dialog
@MainActor
enum Automation {
    nonisolated static let folder: URL? = ProcessInfo.processInfo.environment["RUDE_AWAKENING_AUTOMATION"]
        .flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }
    nonisolated static var isOn: Bool { folder != nil }

    /// Where off-screen windows go.
    static let parking = NSPoint(x: -30_000, y: -30_000)

    private static var handled = 0
    private static var busy = false

    static func start() {
        guard let folder else { return }
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        log("ready, data in \(AppPaths.support.path)")
        let timer = Timer(timeInterval: 0.4, repeats: true) { _ in MainActor.assumeIsolated { poll() } }
        RunLoop.main.add(timer, forMode: .common)
    }

    private static func poll() {
        guard !busy, let folder,
              let text = try? String(contentsOf: folder.appendingPathComponent("commands.txt"), encoding: .utf8) else { return }
        // Only lines that end in a newline are complete.
        var lines = text.components(separatedBy: "\n")
        lines.removeLast()
        guard handled < lines.count else { return }
        let line = lines[handled].trimmed
        handled += 1
        guard !line.isEmpty, !line.hasPrefix("#") else { return }
        busy = true
        Task {
            await run(line)
            busy = false
        }
    }

    private static func run(_ line: String) async {
        let parts = line.split(separator: " ", maxSplits: 1).map(String.init)
        let command = parts[0]
        let rest = parts.count > 1 ? parts[1] : ""
        let store = AlarmStore.shared
        log("> \(line)")

        switch command {
        case "say":
            let started = Date()
            await store.submit(rest)
            if let o = store.outcome {
                log("  reply (\(String(format: "%.1f", Date().timeIntervalSince(started)))s): \(o.reply)")
                for a in o.created {
                    let next = store.nextFire(a).map { Describe.when($0, now: Date(), calendar: store.calendar) } ?? "never"
                    log("  + \(a.displayLabel) | \(Describe.schedule(a, now: Date(), calendar: store.calendar)) | next \(next) | sound \(a.soundID ?? "default")")
                }
                o.deleted.forEach { log("  - deleted \($0.displayLabel)") }
                o.notes.forEach { log("  note: \($0)") }
                o.problems.forEach { log("  problem: \($0)") }
                if o.offline { log("  (offline parser)") }
            }

        case "show":
            switch rest {
            case "settings", "brain": SettingsRouter.shared.tab = .brain; WindowManager.shared.showSettings()
            case "noise": SettingsRouter.shared.tab = .noise; WindowManager.shared.showSettings()
            case "rules": SettingsRouter.shared.tab = .rules; WindowManager.shared.showSettings()
            case "general": SettingsRouter.shared.tab = .general; WindowManager.shared.showSettings()
            case "quick": WindowManager.shared.toggleQuickEntry()
            default: WindowManager.shared.showMain()
            }

        case "snap":
            let bits = rest.split(separator: " ").map(String.init)
            guard bits.count == 2 else { log("  usage: snap <name> <window>"); return }
            try? await Task.sleep(for: .milliseconds(600)) // let animations settle
            snap(bits[1], as: bits[0])

        case "edit-new":
            WindowManager.shared.showMain()
            store.newAlarm()

        case "edit-close":
            store.editing = nil

        case "ring":
            store.testRing(soundID: Prefs.shared.defaultSound)
            log("  ringing: \(store.ringing != nil)")

        case "snooze":
            store.snooze(minutes: Prefs.shared.snoozeMinutes)
            log("  banner: \(store.banner ?? "-")")

        case "stop":
            store.stopRinging()
            log("  ringing: \(store.ringing != nil), banner: \(store.banner ?? "-")")

        case "pref":
            setPref(rest)

        case "alarms":
            for a in store.alarms {
                let next = store.nextFire(a).map { Describe.when($0, now: Date(), calendar: store.calendar) } ?? "-"
                log("  \(a.isEnabled ? "on " : "off") \(a.displayLabel) | \(Describe.schedule(a, now: Date(), calendar: store.calendar)) | next \(next)\(a.snoozedUntil != nil ? " | snoozed" : "")")
            }
            log("  ringing: \(store.ringing.map { $0.labels.joined(separator: ", ") } ?? "no")")

        case "wait":
            try? await Task.sleep(for: .seconds(Double(rest) ?? 1))

        case "quit":
            log("bye")
            WindowManager.shared.quitApp()

        default:
            log("  unknown command")
        }
    }

    private static func setPref(_ text: String) {
        let bits = text.split(separator: " ").map(String.init)
        guard bits.count == 2 else { return }
        let p = Prefs.shared
        let value = bits[1]
        switch bits[0] {
        case "challenge": p.challenge = Challenge(rawValue: value) ?? .off
        case "voiceNag": p.voiceNag = value == "true"
        case "defaultSound": p.defaultSound = value
        case "snoozeMinutes": p.snoozeMinutes = Int(value) ?? 9
        case "skippedOnboarding": p.skippedOnboarding = value == "true"
        default: log("  unknown pref"); return
        }
        log("  \(bits[0]) = \(value)")
    }

    // MARK: Snapshots

    private static var scratchWindows: [NSWindow] = []

    private static func snap(_ which: String, as name: String) {
        guard let folder else { return }
        let window: NSWindow?
        switch which {
        case "menubar":
            window = host(MenuBarPanel(), size: NSSize(width: 360, height: 520))
        case "onboarding":
            window = host(OnboardingView(done: {}).environmentObjects(), size: NSSize(width: 500, height: 640))
        case "sheet":
            window = NSApp.windows.first { $0.identifier?.rawValue == "main" }?.attachedSheet
        default:
            window = NSApp.windows.first { $0.identifier?.rawValue == which && $0.isVisible }
        }
        guard let window, let view = window.contentView?.superview ?? window.contentView else {
            log("  no \(which) window on screen")
            return
        }
        view.layoutSubtreeIfNeeded()
        guard let rep = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
        view.cacheDisplay(in: view.bounds, to: rep)
        let url = folder.appendingPathComponent("\(name).png")
        try? rep.representation(using: .png, properties: [:])?.write(to: url)
        log("  saved \(url.lastPathComponent) (\(Int(view.bounds.width))×\(Int(view.bounds.height)))")
    }

    /// Puts a view in an off-screen window just long enough to photograph it.
    private static func host<V: View>(_ view: V, size: NSSize) -> NSWindow {
        let w = AppWindow(contentRect: NSRect(origin: parking, size: size), styleMask: [.borderless], backing: .buffered, defer: false)
        let host = NSHostingView(rootView: view.frame(width: size.width).fixedSize(horizontal: false, vertical: true))
        w.contentView = host
        w.setContentSize(host.fittingSize)
        w.setFrameOrigin(parking)
        w.orderFrontRegardless()
        scratchWindows.append(w)
        return w
    }

    // MARK: Log

    static func log(_ message: String) {
        guard let folder else { return }
        let url = folder.appendingPathComponent("log.txt")
        let line = "[\(Date().formatted(date: .omitted, time: .standard))] \(message)\n"
        if let handle = try? FileHandle(forWritingTo: url) {
            handle.seekToEndOfFile()
            handle.write(Data(line.utf8))
            try? handle.close()
        } else {
            try? Data(line.utf8).write(to: url)
        }
    }
}

/// A window that may sit off-screen when the test harness asks it to.
final class AppWindow: NSWindow {
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        Automation.isOn ? frameRect : super.constrainFrameRect(frameRect, to: screen)
    }
}
