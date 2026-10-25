import AlarmCore
import AppKit
import SwiftUI

struct RudeAwakeningApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

    var body: some Scene {
        MenuBarExtra(isInserted: .constant(!Automation.isOn)) {
            MenuBarPanel()
        } label: {
            MenuBarLabel()
        }
        .menuBarExtraStyle(.window)
        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") { WindowManager.shared.showSettings() }
                    .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Alarm…") {
                    WindowManager.shared.showMain()
                    AlarmStore.shared.newAlarm()
                }
                .keyboardShortcut("n", modifiers: .command)
                Button("Quick Alarm…") { WindowManager.shared.toggleQuickEntry() }
                    .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(after: .windowArrangement) {
                Button("Rude Awakening") { WindowManager.shared.showMain() }
                    .keyboardShortcut("0", modifiers: .command)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        Prefs.shared.applyDockIcon()
        Automation.start()
        AlarmStore.shared.start()
        HotKeyCenter.shared.onPress = { WindowManager.shared.toggleQuickEntry() }
        HotKeyCenter.shared.apply(Prefs.shared.hotKey)

        let args = CommandLine.arguments
        if Prefs.shared.openWindowAtLaunch || !KeyStore.hasKey || args.contains("--show") {
            WindowManager.shared.showMain()
        }
        if args.contains("--settings") { WindowManager.shared.showSettings() }
        if args.contains("--quick") { WindowManager.shared.toggleQuickEntry() }
        if args.contains("--test-ring") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { AlarmStore.shared.testRing(soundID: Prefs.shared.defaultSound) }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        WindowManager.shared.showMain()
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        // Logging out or shutting down: never block it with a dialog.
        if NSAppleEventManager.shared().currentAppleEvent?.attributeDescriptor(forKeyword: AEKeyword(kAEQuitReason)) != nil {
            return .terminateNow
        }
        if Automation.isOn { return .terminateNow }
        let store = AlarmStore.shared
        if store.ringing != nil { store.stopRinging() }
        let armed = store.upcoming.count
        guard armed > 0 else { return .terminateNow }

        let alert = NSAlert()
        alert.messageText = "Quit and go quiet?"
        alert.informativeText = "If I'm not running, nobody yells at you. \(armed == 1 ? "1 alarm" : "\(armed) alarms") won't ring until you open me again."
        alert.addButton(withTitle: "Keep me running")
        alert.addButton(withTitle: "Quit anyway")
        NSApp.activate(ignoringOtherApps: true)
        return alert.runModal() == .alertSecondButtonReturn ? .terminateNow : .terminateCancel
    }
}
