import Foundation

/// What the language model sends back: the user's intent, not the final dates.
/// `PlanResolver` turns it into real alarms using the Mac's clock and calendar,
/// so the model never has to do date arithmetic.
public struct AlarmPlan: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable {
        public var kind = "once"            // relative | once | repeat
        public var label = ""
        public var offsetDays = 0
        public var offsetHours = 0
        public var offsetMinutes = 0
        public var offsetSeconds = 0
        public var date = ""                // YYYY-MM-DD
        public var time = ""                // HH:MM, 24-hour
        public var frequency = "none"       // none | daily | weekly | monthly | yearly | interval
        public var every = 1
        public var weekdays: [String] = []
        public var dayOfMonth = 0
        public var month = 0
        public var windowEnd = ""
        public var until = ""
        public var sound = ""

        public init() {}

        enum CodingKeys: String, CodingKey {
            case kind, label, date, time, frequency, every, weekdays, month, until, sound
            case offsetDays = "offset_days", offsetHours = "offset_hours"
            case offsetMinutes = "offset_minutes", offsetSeconds = "offset_seconds"
            case dayOfMonth = "day_of_month", windowEnd = "window_end"
        }

        // Models are sloppy: missing keys, nulls, numbers as strings. Accept all of it.
        public init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            kind = c.lenientString(.kind) ?? "once"
            label = c.lenientString(.label) ?? ""
            offsetDays = c.lenientInt(.offsetDays) ?? 0
            offsetHours = c.lenientInt(.offsetHours) ?? 0
            offsetMinutes = c.lenientInt(.offsetMinutes) ?? 0
            offsetSeconds = c.lenientInt(.offsetSeconds) ?? 0
            date = c.lenientString(.date) ?? ""
            time = c.lenientString(.time) ?? ""
            frequency = c.lenientString(.frequency) ?? "none"
            every = c.lenientInt(.every) ?? 1
            weekdays = (try? c.decodeIfPresent([String].self, forKey: .weekdays)) ?? []
            dayOfMonth = c.lenientInt(.dayOfMonth) ?? 0
            month = c.lenientInt(.month) ?? 0
            windowEnd = c.lenientString(.windowEnd) ?? ""
            until = c.lenientString(.until) ?? ""
            sound = c.lenientString(.sound) ?? ""
        }
    }

    public var understood = true
    public var alarms: [Item] = []
    public var deleteIDs: [String] = []
    public var disableIDs: [String] = []
    public var enableIDs: [String] = []
    public var reply = ""

    public init() {}

    enum CodingKeys: String, CodingKey {
        case understood, alarms, reply
        case deleteIDs = "delete_ids", disableIDs = "disable_ids", enableIDs = "enable_ids"
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        understood = (try? c.decodeIfPresent(Bool.self, forKey: .understood)) ?? true
        alarms = (try? c.decodeIfPresent([Item].self, forKey: .alarms)) ?? []
        deleteIDs = (try? c.decodeIfPresent([String].self, forKey: .deleteIDs)) ?? []
        disableIDs = (try? c.decodeIfPresent([String].self, forKey: .disableIDs)) ?? []
        enableIDs = (try? c.decodeIfPresent([String].self, forKey: .enableIDs)) ?? []
        reply = c.lenientString(.reply) ?? ""
    }

    /// Decodes the model's text, tolerating code fences and chatter around the JSON.
    public static func decode(fromModelText text: String) throws -> AlarmPlan {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else {
            throw OpenRouterError.unparseable(text)
        }
        let json = String(text[start...end])
        do {
            return try JSONDecoder().decode(AlarmPlan.self, from: Data(json.utf8))
        } catch {
            throw OpenRouterError.unparseable(text)
        }
    }
}

extension KeyedDecodingContainer {
    func lenientString(_ key: Key) -> String? {
        if let s = try? decodeIfPresent(String.self, forKey: key) { return s }
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return String(i) }
        return nil
    }

    func lenientInt(_ key: Key) -> Int? {
        if let i = try? decodeIfPresent(Int.self, forKey: key) { return i }
        if let d = try? decodeIfPresent(Double.self, forKey: key) { return Int(d.rounded()) }
        if let s = try? decodeIfPresent(String.self, forKey: key) { return Int(s.trimmingCharacters(in: .whitespaces)) }
        return nil
    }
}

/// The outcome of a sentence, ready for the store to apply.
public struct ResolvedPlan: Sendable {
    public var alarms: [Alarm] = []
    public var deleteIDs: [UUID] = []
    public var disableIDs: [UUID] = []
    public var enableIDs: [UUID] = []
    public var reply = ""
    /// Things the app adjusted ("5 PM already passed, so it's tomorrow").
    public var notes: [String] = []
    /// Things it could not do.
    public var problems: [String] = []

    public init() {}

    public var changesSomething: Bool {
        !alarms.isEmpty || !deleteIDs.isEmpty || !disableIDs.isEmpty || !enableIDs.isEmpty
    }
}

public enum PlanResolver {
    public static func resolve(
        _ plan: AlarmPlan,
        prompt: String,
        existing: [Alarm],
        now: Date,
        calendar: Calendar
    ) -> ResolvedPlan {
        var out = ResolvedPlan()
        out.reply = plan.reply.trimmingCharacters(in: .whitespacesAndNewlines)

        for item in plan.alarms {
            switch resolve(item, prompt: prompt, now: now, calendar: calendar) {
            case .success(let (alarm, note)):
                out.alarms.append(alarm)
                if let note { out.notes.append(note) }
            case .failure(let problem):
                out.problems.append(problem.message)
            }
        }

        out.deleteIDs = match(plan.deleteIDs, in: existing)
        out.disableIDs = match(plan.disableIDs, in: existing).filter { !out.deleteIDs.contains($0) }
        out.enableIDs = match(plan.enableIDs, in: existing).filter { !out.deleteIDs.contains($0) }
        return out
    }

    public struct Problem: Error, Sendable {
        public let message: String
        init(_ message: String) { self.message = message }
    }

    public static func resolve(
        _ item: AlarmPlan.Item,
        prompt: String,
        now: Date,
        calendar cal: Calendar
    ) -> Result<(Alarm, String?), Problem> {
        let label = String(item.label.trimmingCharacters(in: .whitespacesAndNewlines).prefix(60))
        let sound = SoundLibrary.ids.contains(item.sound.lowercased()) ? item.sound.lowercased() : nil
        func make(_ schedule: Alarm.Schedule) -> Alarm {
            Alarm(label: label, schedule: schedule, soundID: sound, createdAt: now, prompt: prompt)
        }

        let offset = item.offsetDays * 86_400 + item.offsetHours * 3_600 + item.offsetMinutes * 60 + item.offsetSeconds
        let kind = item.kind.lowercased()
        let frequency = item.frequency.lowercased()

        if kind == "relative" || (kind != "repeat" && frequency == "none" && item.time.isEmpty && offset > 0) {
            guard offset > 0 else { return .failure(Problem("“In zero minutes” is just now. Give me a real duration.")) }
            guard offset <= 366 * 86_400 else { return .failure(Problem("More than a year away? Put that in a calendar, not an alarm.")) }
            var fire = cal.date(byAdding: .day, value: item.offsetDays, to: now) ?? now
            fire = fire.addingTimeInterval(TimeInterval(offset - item.offsetDays * 86_400))
            return .success((make(.once(fire)), nil))
        }

        if kind == "repeat" || frequency != "none" {
            return resolveRepeat(item, offset: offset, now: now, cal: cal).map { (make(.repeating($0.0)), $0.1) }
        }

        // A single alarm at a clock time.
        guard let time = TimeOfDay(string: item.time) else {
            return .failure(Problem("I couldn't work out a time from that. Try “at 7:30 am”."))
        }
        let explicitDay = item.date.isEmpty ? nil : cal.day(fromISO: item.date)
        if !item.date.isEmpty && explicitDay == nil {
            return .failure(Problem("“\(item.date)” isn't a date I recognise."))
        }
        let today = cal.startOfDay(for: now)
        let day = explicitDay ?? today
        guard var fire = time.on(day, calendar: cal) else {
            return .failure(Problem("That time doesn't exist on that day."))
        }
        var note: String?
        if fire <= now {
            if day == today {
                fire = time.on(cal.addingDays(1, to: today), calendar: cal) ?? fire.addingTimeInterval(86_400)
                note = "\(Describe.time(time, calendar: cal)) already passed today, so I set it for tomorrow."
            } else {
                return .failure(Problem("\(Describe.when(fire, now: now, calendar: cal)) is in the past. I can't time travel. Yet."))
            }
        }
        if fire.timeIntervalSince(now) > 5 * 366 * 86_400 {
            return .failure(Problem("That's years away. I'll be a legacy app by then."))
        }
        return .success((make(.once(fire)), note))
    }

    private static func resolveRepeat(
        _ item: AlarmPlan.Item,
        offset: Int,
        now: Date,
        cal: Calendar
    ) -> Result<(Recurrence, String?), Problem> {
        let time = TimeOfDay(string: item.time)
        let startDay = item.date.isEmpty ? nil : cal.day(fromISO: item.date)
        let weekdays = Set(item.weekdays.compactMap(Weekday.number(for:)))
        let until = item.until.isEmpty ? nil : cal.day(fromISO: item.until)
        if let until, until < cal.startOfDay(for: now) {
            return .failure(Problem("That repeat ends before it starts."))
        }

        var rule: Recurrence
        switch item.frequency.lowercased() {
        case "daily":
            guard let time else { return .failure(Problem("Every day at… what time?")) }
            let anchor: Date
            if let startDay {
                anchor = startDay
            } else {
                // First ring is the next time this clock time comes round.
                let today = cal.startOfDay(for: now)
                let passed = (time.on(today, calendar: cal) ?? now) <= now
                anchor = passed ? cal.addingDays(1, to: today) : today
            }
            rule = .daily(at: time, every: max(1, item.every), startingOn: anchor)

        case "weekly":
            guard let time else { return .failure(Problem("Which time on those days?")) }
            var days = weekdays
            if days.isEmpty, let startDay { days = [cal.component(.weekday, from: startDay)] }
            guard !days.isEmpty else { return .failure(Problem("Which days of the week?")) }
            rule = .weekly(at: time, on: days)

        case "monthly":
            guard let time else { return .failure(Problem("Monthly at what time?")) }
            var day = item.dayOfMonth
            if day <= 0 { day = cal.component(.day, from: startDay ?? now) }
            guard (1...31).contains(day) else { return .failure(Problem("Day \(day) of the month? Bold.")) }
            rule = .monthly(at: time, day: day)

        case "yearly":
            guard let time else { return .failure(Problem("Yearly at what time?")) }
            var month = item.month, day = item.dayOfMonth
            if month <= 0 || day <= 0, let startDay {
                month = cal.component(.month, from: startDay)
                day = cal.component(.day, from: startDay)
            }
            guard (1...12).contains(month), (1...31).contains(day) else {
                return .failure(Problem("Which day of the year?"))
            }
            rule = .yearly(at: time, month: month, day: day)

        case "interval":
            let minutes = item.every
            guard minutes >= 1 else { return .failure(Problem("Every how many minutes?")) }
            guard minutes <= 7 * 24 * 60 else { return .failure(Problem("That interval is longer than a week. Try a weekly alarm.")) }
            if let time, let end = TimeOfDay(string: item.windowEnd) {
                rule = .interval(minutes: minutes, from: time, to: end, on: weekdays)
            } else {
                let anchor: Date
                if offset > 0 {
                    anchor = now.addingTimeInterval(TimeInterval(offset))
                } else if let time {
                    let day = startDay ?? cal.startOfDay(for: now)
                    let candidate = time.on(day, calendar: cal) ?? now
                    anchor = candidate > now ? candidate : (time.on(cal.addingDays(1, to: day), calendar: cal) ?? now)
                } else {
                    anchor = now.addingTimeInterval(TimeInterval(minutes * 60))
                }
                rule = .interval(minutes: minutes, firstAt: anchor)
                rule.weekdays = weekdays
            }

        default:
            return .failure(Problem("I don't know how to repeat “\(item.frequency)”."))
        }

        rule.until = until
        guard rule.next(after: now, calendar: cal) != nil else {
            return .failure(Problem("That repeat never actually rings. Check the end date."))
        }
        return .success((rule, nil))
    }

    /// Maps the short ids the model returns back to real alarm ids.
    static func match(_ ids: [String], in alarms: [Alarm]) -> [UUID] {
        var out: [UUID] = []
        for raw in ids {
            let key = raw.lowercased().trimmingCharacters(in: .whitespaces)
            guard key.count >= 4 else { continue }
            if let hit = alarms.first(where: { $0.id.uuidString.lowercased().hasPrefix(key) }), !out.contains(hit.id) {
                out.append(hit.id)
            }
        }
        return out
    }
}
