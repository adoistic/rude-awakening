import AlarmCore
import AppKit
import Combine
import SwiftUI

/// One ringing episode. Several alarms that go off together share it.
struct RingSession: Equatable {
    struct Reason: Equatable, Identifiable {
        let id: UUID
        /// What the alarm is for ("Call mom"). Empty when the user never said.
        let label: String
        /// The sentence the user typed to create it, if any.
        let prompt: String?
        let schedule: String
    }

    var reasons: [Reason]
    var soundID: String
    var startedAt: Date
    var isTest: Bool
    var volumeFights = 0

    var alarmIDs: [UUID] { reasons.map(\.id) }
    var labels: [String] { reasons.map(\.label).filter { !$0.isEmpty } }
}

/// What happened after the user typed a sentence, so the UI can show it and undo it.
struct CommandOutcome: Identifiable {
    let id = UUID()
    var text: String
    var reply: String
    var created: [Alarm] = []
    var deleted: [Alarm] = []
    var toggled: [(id: UUID, wasEnabled: Bool)] = []
    var notes: [String] = []
    var problems: [String] = []
    var offline = false
    var undone = false

    var changedSomething: Bool { !created.isEmpty || !deleted.isEmpty || !toggled.isEmpty }
}

@MainActor
final class AlarmStore: ObservableObject {
    static let shared = AlarmStore()

    @Published private(set) var alarms: [Alarm] = []
    @Published private(set) var ringing: RingSession?
    @Published private(set) var isThinking = false
    @Published var outcome: CommandOutcome?
    @Published var banner: String?
    /// The alarm open in the editor sheet (a fresh one for "add by hand").
    @Published var editing: Alarm?

    let calendar = Calendar.autoupdatingCurrent
    private var timer: Timer?
    private var activity: NSObjectProtocol?
    private var activityKind = ""
    private var bag = Set<AnyCancellable>()

    // MARK: Lifecycle

    func start() {
        load()
        let timer = Timer(timeInterval: 1, repeats: true) { _ in
            MainActor.assumeIsolated { AlarmStore.shared.tick() }
        }
        timer.tolerance = 0.1
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer

        let wake = NSWorkspace.shared.notificationCenter
        wake.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { AlarmStore.shared.tick() }
        }
        for name in [Notification.Name.NSSystemTimeZoneDidChange, .NSSystemClockDidChange] {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { _ in
                MainActor.assumeIsolated {
                    AlarmStore.shared.objectWillChange.send()
                    AlarmStore.shared.tick()
                }
            }
        }
        Prefs.shared.$keepAwake.dropFirst().sink { _ in
            DispatchQueue.main.async { AlarmStore.shared.updateActivity() }
        }.store(in: &bag)

        updateActivity()
        AlarmPlayer.prewarm()
        tick()
    }

    /// Runs every second (and on wake): rings whatever is due.
    func tick() {
        let now = Date()
        Ticker.shared.now = now
        var copy = alarms
        let result = AlarmEngine.tick(&copy, now: now, calendar: calendar)
        if !result.isEmpty {
            alarms = copy
            save()
            if !result.missed.isEmpty {
                let names = copy.filter { result.missed.contains($0.id) }.map { $0.label.isEmpty ? "an alarm" : "“\($0.label)”" }
                banner = "Your Mac was asleep and missed \(names.joined(separator: ", ")). I'd have yelled, I promise."
            }
            if !result.ring.isEmpty { beginRinging(result.ring, isTest: false) }
            updateActivity()
        }
        if let session = ringing, !session.isTest, Prefs.shared.autoStopMinutes > 0,
           now.timeIntervalSince(session.startedAt) > Double(Prefs.shared.autoStopMinutes * 60) {
            stopRinging(gaveUp: true)
        }
    }

    // MARK: Queries

    func nextFire(_ alarm: Alarm) -> Date? { alarm.nextFire(calendar: calendar) }

    var upcoming: [Alarm] {
        alarms.filter { nextFire($0) != nil }.sorted { (nextFire($0) ?? .distantFuture) < (nextFire($1) ?? .distantFuture) }
    }

    var paused: [Alarm] {
        alarms.filter { nextFire($0) == nil && !$0.isFinished }.sorted { $0.createdAt > $1.createdAt }
    }

    var finished: [Alarm] {
        alarms.filter { $0.isFinished && nextFire($0) == nil }.sorted { ($0.lastTriggeredAt ?? .distantPast) > ($1.lastTriggeredAt ?? .distantPast) }
    }

    var nextUp: (alarm: Alarm, date: Date)? {
        upcoming.first.flatMap { a in nextFire(a).map { (a, $0) } }
    }

    var hasArmedAlarms: Bool { alarms.contains { nextFire($0) != nil } }

    // MARK: Typing a sentence

    @discardableResult
    func submit(_ raw: String) async -> Bool {
        let text = raw.trimmed
        guard !text.isEmpty, !isThinking else { return false }
        isThinking = true
        defer { isThinking = false }

        let now = Date()
        var resolved: ResolvedPlan
        var offline = false
        var lead: String?

        if let key = KeyStore.load() {
            do {
                let client = OpenRouterClient(apiKey: key, model: Prefs.shared.model)
                let prompt = Prompt.system(now: now, calendar: calendar, existing: alarms)
                let plan = try await client.plan(for: text, systemPrompt: prompt)
                resolved = PlanResolver.resolve(plan, prompt: text, existing: alarms, now: now, calendar: calendar)
            } catch let error as OpenRouterError where error.isConnectivity {
                resolved = LocalParser.parse(text, now: now, calendar: calendar)
                offline = true
                lead = "\(error.localizedDescription) My tiny offline brain took over."
            } catch {
                outcome = CommandOutcome(text: text, reply: "", problems: [error.localizedDescription])
                return false
            }
        } else {
            resolved = LocalParser.parse(text, now: now, calendar: calendar)
            offline = true
            lead = "No OpenRouter key yet, so my tiny offline brain handled this. Add one in Settings for the clever stuff."
        }

        apply(resolved, text: text, offline: offline, lead: lead)
        return resolved.changesSomething
    }

    private func apply(_ r: ResolvedPlan, text: String, offline: Bool, lead: String?) {
        var o = CommandOutcome(text: text, reply: r.reply, notes: r.notes, problems: r.problems, offline: offline)
        if let lead { o.notes.insert(lead, at: 0) }

        o.deleted = alarms.filter { r.deleteIDs.contains($0.id) }
        alarms.removeAll { r.deleteIDs.contains($0.id) }
        for id in r.disableIDs {
            guard let i = index(id) else { continue }
            o.toggled.append((id, alarms[i].isEnabled))
            alarms[i].isEnabled = false
            alarms[i].snoozedUntil = nil
        }
        for id in r.enableIDs {
            guard let i = index(id) else { continue }
            o.toggled.append((id, alarms[i].isEnabled))
            AlarmEngine.enable(&alarms[i], now: Date(), calendar: calendar)
        }
        alarms.append(contentsOf: r.alarms)
        o.created = r.alarms
        if o.reply.isEmpty, o.changedSomething { o.reply = Cheek.pick(Cheek.doneReplies) }

        outcome = o
        save()
        updateActivity()
    }

    func undo() {
        guard var o = outcome, !o.undone, o.changedSomething else { return }
        let created = Set(o.created.map(\.id))
        alarms.removeAll { created.contains($0.id) }
        alarms.append(contentsOf: o.deleted)
        for (id, was) in o.toggled {
            if let i = index(id) { alarms[i].isEnabled = was }
        }
        o.undone = true
        outcome = o
        save()
        updateActivity()
    }

    // MARK: Editing by hand

    func upsert(_ alarm: Alarm) {
        var a = alarm
        if let i = index(a.id) {
            if alarms[i].schedule != a.schedule {
                a.armedAt = Date()
                a.lastTriggeredAt = nil
                a.snoozedUntil = nil
                a.isEnabled = true
            }
            alarms[i] = a
        } else {
            a.armedAt = Date()
            alarms.append(a)
        }
        save()
        updateActivity()
    }

    func setEnabled(_ id: UUID, _ on: Bool) {
        guard let i = index(id) else { return }
        if on {
            AlarmEngine.enable(&alarms[i], now: Date(), calendar: calendar)
        } else {
            alarms[i].isEnabled = false
            alarms[i].snoozedUntil = nil
        }
        save()
        updateActivity()
    }

    func delete(_ id: UUID) {
        alarms.removeAll { $0.id == id }
        save()
        updateActivity()
    }

    func duplicate(_ id: UUID) {
        guard let a = alarms.first(where: { $0.id == id }) else { return }
        var copy = Alarm(label: a.label, schedule: a.schedule, soundID: a.soundID, prompt: a.prompt)
        AlarmEngine.enable(&copy, now: Date(), calendar: calendar)
        alarms.append(copy)
        save()
        updateActivity()
    }

    func clearFinished() {
        alarms.removeAll { $0.isFinished && nextFire($0) == nil }
        save()
    }

    func newAlarm() {
        let start = calendar.date(byAdding: .hour, value: 1, to: Date()) ?? Date()
        let rounded = calendar.date(bySetting: .minute, value: 0, of: start) ?? start
        editing = Alarm(schedule: .once(rounded), soundID: nil)
    }

    private func index(_ id: UUID) -> Int? { alarms.firstIndex { $0.id == id } }

    // MARK: Ringing

    func testRing(_ alarm: Alarm) {
        beginRinging([alarm.id], isTest: true, extra: alarm)
    }

    func testRing(soundID: String) {
        let demo = Alarm(label: "Test drive", schedule: .once(Date()), soundID: soundID, prompt: "make some noise")
        beginRinging([demo.id], isTest: true, extra: demo)
    }

    private func beginRinging(_ ids: [UUID], isTest: Bool, extra: Alarm? = nil) {
        let now = Date()
        var rung = alarms.filter { ids.contains($0.id) }
        if let extra, !rung.contains(where: { $0.id == extra.id }) { rung.append(extra) }
        let reasons = rung.map {
            RingSession.Reason(id: $0.id, label: $0.label, prompt: $0.prompt, schedule: Describe.schedule($0, now: now, calendar: calendar))
        }

        if var session = ringing {
            for r in reasons where !session.alarmIDs.contains(r.id) { session.reasons.append(r) }
            ringing = session
            return
        }

        let prefs = Prefs.shared
        let sound = rung.first?.soundID ?? prefs.defaultSound
        let session = RingSession(reasons: reasons, soundID: sound, startedAt: now, isTest: isTest)
        ringing = session

        let time = Describe.time(now, calendar: calendar)
        AlarmPlayer.shared.startAlarm(
            soundID: sound,
            crankTo: (!isTest && prefs.crankVolume) ? Float(prefs.crankLevel) : nil,
            lockVolume: !isTest && prefs.crankVolume && prefs.volumeLock,
            voiceLines: prefs.voiceNag ? Cheek.spokenLines(labels: session.labels, time: time) : [],
            onVolumeFight: { AlarmStore.shared.ringing?.volumeFights += 1 }
        )
        RingWindowManager.shared.show()
        if !Automation.isOn { Power.wakeDisplay() }
        updateActivity()
    }

    func snooze(minutes: Int) {
        guard let session = ringing else { return }
        let until = Date().addingTimeInterval(Double(minutes * 60))
        if !session.isTest {
            for id in session.alarmIDs {
                if let i = index(id) { AlarmEngine.snooze(&alarms[i], until: until) }
            }
            save()
        }
        endSession()
        banner = Cheek.snoozed(until: Describe.time(until, calendar: calendar), labels: session.labels)
    }

    func stopRinging(gaveUp: Bool = false) {
        guard let session = ringing else { return }
        if !session.isTest {
            for id in session.alarmIDs {
                if let i = index(id) { AlarmEngine.dismiss(&alarms[i]) }
            }
            save()
        }
        endSession()
        if gaveUp {
            let what = session.labels.isEmpty ? "your alarm" : "“\(session.labels.joined(separator: "”, “"))”"
            banner = "You slept through \(what). I yelled for \(Prefs.shared.autoStopMinutes) minutes. Honestly impressive."
        } else if !session.isTest {
            banner = Cheek.pick(Cheek.stopped)
        }
    }

    private func endSession() {
        AlarmPlayer.shared.stopAlarm()
        RingWindowManager.shared.hide()
        ringing = nil
        updateActivity()
    }

    // MARK: Staying awake

    /// Keeps timers precise (no App Nap) while anything is armed and, if allowed, stops idle sleep.
    private func updateActivity() {
        let armed = hasArmedAlarms || ringing != nil
        let kind: String
        var options: ProcessInfo.ActivityOptions = []
        if ringing != nil {
            kind = "ringing"
            options = [.userInitiated, .idleDisplaySleepDisabled]
        } else if armed && Prefs.shared.keepAwake {
            kind = "awake"
            options = [.userInitiated]
        } else if armed {
            kind = "armed"
            options = [.userInitiatedAllowingIdleSystemSleep]
        } else {
            kind = ""
        }
        guard kind != activityKind else { return }
        if let activity { ProcessInfo.processInfo.endActivity(activity) }
        activity = kind.isEmpty ? nil : ProcessInfo.processInfo.beginActivity(options: options, reason: "Rude Awakening has alarms to ring")
        activityKind = kind
    }

    // MARK: Saving

    private func load() {
        guard let data = try? Data(contentsOf: AppPaths.alarms) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            alarms = try decoder.decode([Alarm].self, from: data)
        } catch {
            // Keep the unreadable file for inspection rather than overwriting it.
            let backup = AppPaths.support.appendingPathComponent("alarms-unreadable-\(Int(Date().timeIntervalSince1970)).json")
            try? FileManager.default.copyItem(at: AppPaths.alarms, to: backup)
            banner = "I couldn't read your saved alarms, so I kept a copy at \(backup.lastPathComponent)."
        }
    }

    private func save() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(alarms) else { return }
        try? data.write(to: AppPaths.alarms, options: .atomic)
    }
}
