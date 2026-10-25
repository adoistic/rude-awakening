import AppKit
import SwiftUI

/// The app's windows are plain AppKit windows hosting SwiftUI, so they can be opened from
/// anywhere (menu bar, hot key, launch) and sit above everything when an alarm rings.
@MainActor
final class WindowManager: NSObject, NSWindowDelegate {
    static let shared = WindowManager()

    private var main: NSWindow?
    private var settings: NSWindow?
    private var quick: QuickPanel?

    func showMain() {
        if main == nil {
            let w = AppWindow(
                contentRect: NSRect(x: 0, y: 0, width: 600, height: 780),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            w.title = "Rude Awakening"
            w.identifier = NSUserInterfaceItemIdentifier("main")
            w.titleVisibility = .hidden
            w.titlebarAppearsTransparent = true
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 520, height: 560)
            w.contentView = NSHostingView(rootView: MainView().environmentObjects())
            w.center()
            w.setFrameAutosaveName("RudeAwakeningMain")
            main = w
        }
        present(main)
    }

    func showSettings() {
        if settings == nil {
            let w = AppWindow(
                contentRect: NSRect(x: 0, y: 0, width: 620, height: 600),
                styleMask: [.titled, .closable, .miniaturizable, .resizable],
                backing: .buffered,
                defer: false
            )
            w.title = "Rude Awakening Settings"
            w.identifier = NSUserInterfaceItemIdentifier("settings")
            w.isReleasedWhenClosed = false
            w.minSize = NSSize(width: 560, height: 480)
            w.contentView = NSHostingView(rootView: SettingsView().environmentObjects())
            w.center()
            w.setFrameAutosaveName("RudeAwakeningSettings")
            settings = w
        }
        present(settings)
    }

    /// Brings a window forward, or parks it off-screen without taking focus for the test harness.
    private func present(_ window: NSWindow?) {
        guard let window else { return }
        if Automation.isOn {
            window.setFrameOrigin(Automation.parking)
            window.orderFrontRegardless()
            return
        }
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// The Spotlight-style box behind the global shortcut.
    func toggleQuickEntry() {
        if let quick, quick.isVisible {
            quick.orderOut(nil)
            return
        }
        if quick == nil {
            let panel = QuickPanel(
                contentRect: NSRect(x: 0, y: 0, width: 640, height: 90),
                styleMask: [.borderless, .nonactivatingPanel, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            panel.isFloatingPanel = true
            panel.level = .floating
            panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = true
            panel.isMovableByWindowBackground = true
            panel.hidesOnDeactivate = false
            panel.delegate = self
            panel.identifier = NSUserInterfaceItemIdentifier("quick")
            let host = NSHostingController(rootView: QuickEntryView(close: { WindowManager.shared.hideQuickEntry() }).environmentObjects())
            host.sizingOptions = [.preferredContentSize]
            panel.contentViewController = host
            quick = panel
        }
        guard let quick, let screen = NSScreen.main else { return }
        if Automation.isOn {
            quick.setFrameOrigin(Automation.parking)
            quick.orderFrontRegardless()
            return
        }
        let frame = screen.visibleFrame
        quick.setFrameTopLeftPoint(NSPoint(x: frame.midX - 320, y: frame.minY + frame.height * 0.72))
        quick.makeKeyAndOrderFront(nil)
        NotificationCenter.default.post(name: .quickEntryOpened, object: nil)
    }

    /// Quits even when a sheet is open (AppKit otherwise refuses to terminate under a sheet).
    func quitApp() {
        for window in NSApp.windows {
            if let sheet = window.attachedSheet { window.endSheet(sheet) }
        }
        DispatchQueue.main.async { NSApp.terminate(nil) }
    }

    func hideQuickEntry() {
        quick?.orderOut(nil)
    }

    func windowDidResignKey(_ notification: Notification) {
        if let quick, notification.object as? QuickPanel === quick, !AlarmStore.shared.isThinking {
            quick.orderOut(nil)
        }
    }
}

extension Notification.Name {
    static let quickEntryOpened = Notification.Name("RudeAwakeningQuickEntryOpened")
}

final class QuickPanel: NSPanel {
    override var canBecomeKey: Bool { true }
}

/// Full-screen ringing windows: one per display, above everything, on every Space.
@MainActor
final class RingWindowManager {
    static let shared = RingWindowManager()
    private var windows: [NSWindow] = []

    func show() {
        hide()
        let screens = Automation.isOn ? Array(NSScreen.screens.prefix(1)) : NSScreen.screens
        for (i, screen) in screens.enumerated() {
            let w = RingWindow(contentRect: screen.frame, styleMask: [.borderless, .fullSizeContentView], backing: .buffered, defer: false)
            w.identifier = NSUserInterfaceItemIdentifier(i == 0 ? "ring" : "ring-\(i)")
            w.level = .screenSaver
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.isOpaque = true
            w.backgroundColor = .black
            w.hasShadow = false
            w.isReleasedWhenClosed = false
            w.contentView = NSHostingView(rootView: RingingView(isPrimary: i == 0).environmentObjects())
            w.setFrame(screen.frame, display: true)
            windows.append(w)
            if Automation.isOn {
                w.setFrameOrigin(Automation.parking)
                w.orderFrontRegardless()
                continue
            }
            if i == 0 { w.makeKeyAndOrderFront(nil) } else { w.orderFrontRegardless() }
        }
        guard !Automation.isOn else { return }
        NSApp.activate(ignoringOtherApps: true)
        windows.first?.makeKey()
    }

    func hide() {
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
    }
}

final class RingWindow: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

extension View {
    func environmentObjects() -> some View {
        environmentObject(AlarmStore.shared)
            .environmentObject(Prefs.shared)
            .environmentObject(Ticker.shared)
            .environmentObject(AlarmPlayer.shared)
    }
}
