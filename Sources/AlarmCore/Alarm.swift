import Foundation

public struct Alarm: Codable, Identifiable, Hashable, Sendable {
    public enum Schedule: Codable, Hashable, Sendable {
        /// A single ring at an exact instant.
        case once(Date)
        /// A repeating ring.
        case repeating(Recurrence)
    }

    public var id: UUID
    /// What the alarm is for ("Call mom"). May be empty.
    public var label: String
    public var schedule: Schedule
    /// A sound id from `SoundLibrary`, "file:<name>" for a custom sound, or nil for the default.
    public var soundID: String?
    public var isEnabled: Bool
    public var createdAt: Date
    /// When the alarm was last switched on. Repeating alarms never ring for times before this.
    public var armedAt: Date
    /// When the alarm last went off (rang or was skipped as missed).
    public var lastTriggeredAt: Date?
    /// Set while snoozed: the alarm rings again at this instant.
    public var snoozedUntil: Date?
    /// What the user typed to create it, if it came from a sentence.
    public var prompt: String?

    public init(
        id: UUID = UUID(),
        label: String = "",
        schedule: Schedule,
        soundID: String? = nil,
        isEnabled: Bool = true,
        createdAt: Date = Date(),
        prompt: String? = nil
    ) {
        self.id = id
        self.label = label
        self.schedule = schedule
        self.soundID = soundID
        self.isEnabled = isEnabled
        self.createdAt = createdAt
        self.armedAt = createdAt
        self.lastTriggeredAt = nil
        self.snoozedUntil = nil
        self.prompt = prompt
    }

    private enum CodingKeys: String, CodingKey {
        case id, label, schedule, soundID, isEnabled, createdAt, armedAt, lastTriggeredAt, snoozedUntil, prompt
    }

    // Lenient decoding so older alarm files keep loading as fields are added.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(UUID.self, forKey: .id) ?? UUID()
        label = try c.decodeIfPresent(String.self, forKey: .label) ?? ""
        schedule = try c.decode(Schedule.self, forKey: .schedule)
        soundID = try c.decodeIfPresent(String.self, forKey: .soundID)
        isEnabled = try c.decodeIfPresent(Bool.self, forKey: .isEnabled) ?? true
        createdAt = try c.decodeIfPresent(Date.self, forKey: .createdAt) ?? Date()
        armedAt = try c.decodeIfPresent(Date.self, forKey: .armedAt) ?? createdAt
        lastTriggeredAt = try c.decodeIfPresent(Date.self, forKey: .lastTriggeredAt)
        snoozedUntil = try c.decodeIfPresent(Date.self, forKey: .snoozedUntil)
        prompt = try c.decodeIfPresent(String.self, forKey: .prompt)
    }

    public var isOneOff: Bool {
        if case .once = schedule { return true }
        return false
    }

    public var onceDate: Date? {
        if case .once(let d) = schedule { return d }
        return nil
    }

    public var recurrence: Recurrence? {
        if case .repeating(let r) = schedule { return r }
        return nil
    }

    /// A one-off alarm that has rung and is not snoozed.
    public var isFinished: Bool { isOneOff && lastTriggeredAt != nil && snoozedUntil == nil }

    /// When this alarm goes off next, or nil when it is off or finished.
    public func nextFire(calendar: Calendar) -> Date? {
        guard isEnabled else { return nil }
        if let snoozedUntil { return snoozedUntil }
        switch schedule {
        case .once(let date):
            return lastTriggeredAt == nil ? date : nil
        case .repeating(let rule):
            let reference = max(lastTriggeredAt ?? armedAt, armedAt)
            return rule.next(after: reference, calendar: calendar)
        }
    }

    /// The short id shown to the language model ("1a2b3c4d").
    public var shortID: String { String(id.uuidString.prefix(8)).lowercased() }
}

/// The pure scheduling rules: what rings, what was missed, what snoozing and stopping do.
public enum AlarmEngine {
    /// Alarms found more than this late (the Mac was asleep or off) are skipped, not rung.
    public static let lateGrace: TimeInterval = 60 * 60

    public struct TickResult: Sendable, Equatable {
        public var ring: [UUID] = []
        public var missed: [UUID] = []
        public var isEmpty: Bool { ring.isEmpty && missed.isEmpty }
    }

    /// Marks every alarm that is due at `now` as triggered and reports which to ring.
    public static func tick(_ alarms: inout [Alarm], now: Date, calendar: Calendar) -> TickResult {
        var result = TickResult()
        for i in alarms.indices {
            guard var fire = alarms[i].nextFire(calendar: calendar), fire <= now else { continue }
            // After a long sleep, judge lateness by the most recent due time, not the oldest skipped one.
            if case .repeating(let rule) = alarms[i].schedule, alarms[i].snoozedUntil == nil {
                var steps = 0
                while steps < 10_000, let later = rule.next(after: fire, calendar: calendar), later <= now {
                    fire = later
                    steps += 1
                }
            }
            alarms[i].lastTriggeredAt = now
            alarms[i].snoozedUntil = nil
            if now.timeIntervalSince(fire) > lateGrace {
                if alarms[i].isOneOff { alarms[i].isEnabled = false }
                result.missed.append(alarms[i].id)
            } else {
                result.ring.append(alarms[i].id)
            }
        }
        return result
    }

    public static func snooze(_ alarm: inout Alarm, until date: Date) {
        alarm.snoozedUntil = date
    }

    /// Stopping a ringing alarm: one-offs switch off, repeating alarms wait for their next time.
    public static func dismiss(_ alarm: inout Alarm) {
        alarm.snoozedUntil = nil
        if alarm.isOneOff { alarm.isEnabled = false }
    }

    /// Switching an alarm on. A finished or past one-off moves to the next time its clock time comes round.
    public static func enable(_ alarm: inout Alarm, now: Date, calendar: Calendar) {
        alarm.isEnabled = true
        alarm.armedAt = now
        alarm.snoozedUntil = nil
        if case .once(let date) = alarm.schedule {
            alarm.lastTriggeredAt = nil
            if date <= now {
                let time = TimeOfDay(date: date, calendar: calendar)
                var day = calendar.startOfDay(for: now)
                if let today = time.on(day, calendar: calendar), today <= now { day = calendar.addingDays(1, to: day) }
                alarm.schedule = .once(time.on(day, calendar: calendar) ?? now.addingTimeInterval(86_400))
            }
        }
    }
}
