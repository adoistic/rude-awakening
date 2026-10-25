import AppKit
import Foundation
import IOKit.pwr_mgt
import ServiceManagement

/// Where the app keeps its things: ~/Library/Application Support/Rude Awakening.
enum AppPaths {
    static let support: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let url = Automation.folder?.appendingPathComponent("support", isDirectory: true)
            ?? base.appendingPathComponent("Rude Awakening", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }()

    static var alarms: URL { support.appendingPathComponent("alarms.json") }
    static var key: URL { support.appendingPathComponent("openrouter-key") }

    static var sounds: URL {
        let url = support.appendingPathComponent("Sounds", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// The OpenRouter key lives in one file only its owner can read, and is only ever sent to openrouter.ai.
/// (Not the Keychain: an unsigned open-source app gets a new identity with every update,
/// and the Keychain would ask for your password each time.)
enum KeyStore {
    static func load() -> String? {
        guard let text = try? String(contentsOf: AppPaths.key, encoding: .utf8) else { return nil }
        let key = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return key.isEmpty ? nil : key
    }

    static var hasKey: Bool { load() != nil }

    static func save(_ key: String) throws {
        let path = AppPaths.key.path
        try? FileManager.default.removeItem(atPath: path)
        let ok = FileManager.default.createFile(
            atPath: path,
            contents: Data(key.trimmingCharacters(in: .whitespacesAndNewlines).utf8),
            attributes: [.posixPermissions: 0o600]
        )
        if !ok { throw CocoaError(.fileWriteUnknown) }
    }

    static func remove() {
        try? FileManager.default.removeItem(at: AppPaths.key)
    }
}

enum Power {
    /// Turns the display on if it was asleep, like touching the trackpad would.
    static func wakeDisplay() {
        var id: IOPMAssertionID = 0
        IOPMAssertionDeclareUserActivity("Rude Awakening is ringing" as CFString, kIOPMUserActiveLocal, &id)
    }
}

enum LaunchAtLogin {
    static var isEnabled: Bool { SMAppService.mainApp.status == .enabled }
    static var needsApproval: Bool { SMAppService.mainApp.status == .requiresApproval }

    static func set(_ on: Bool) throws {
        if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }

    static func openSystemSettings() {
        SMAppService.openSystemSettingsLoginItems()
    }
}

/// Publishes the current second, for countdowns. Only views that show a countdown observe it.
@MainActor
final class Ticker: ObservableObject {
    static let shared = Ticker()
    @Published var now = Date()
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
