import Foundation

/// How a repeating alarm repeats. All times are wall-clock times in the Mac's
/// current time zone, so "every day at 7:00" stays at 7:00 across DST and travel.
public struct Recurrence: Codable, Hashable, Sendable {
    public enum Frequency: String, Codable, CaseIterable, Sendable {
        case daily, weekly, monthly, yearly, interval
    }

    public var frequency: Frequency
    /// Ring time for daily/weekly/monthly/yearly. For `interval` with a window, the window start;
    /// for `interval` without a window it is unused.
    public var time: TimeOfDay
    /// Every N days (daily) or every N minutes (interval). Ignored otherwise.
    public var every: Int
    /// Calendar weekdays (1 = Sunday). Required for weekly; an optional day filter for interval.
    public var weekdays: Set<Int>
    /// Day of month for monthly and yearly. Clamped to the month's length (31 = last day).
    public var dayOfMonth: Int
    /// Month (1–12) for yearly.
    public var month: Int
    /// End of the daily window for `interval`. Nil means the interval runs around the clock.
    public var windowEnd: TimeOfDay?
    /// First ring for `interval` without a window; first day for "every N days".
    public var anchor: Date
    /// Last day (inclusive) on which the alarm may ring.
    public var until: Date?

    public init(
        frequency: Frequency,
        time: TimeOfDay = TimeOfDay(hour: 8, minute: 0),
        every: Int = 1,
        weekdays: Set<Int> = [],
        dayOfMonth: Int = 1,
        month: Int = 1,
        windowEnd: TimeOfDay? = nil,
        anchor: Date = Date(),
        until: Date? = nil
    ) {
        self.frequency = frequency
        self.time = time
        self.every = max(1, every)
        self.weekdays = weekdays
        self.dayOfMonth = dayOfMonth
        self.month = month
        self.windowEnd = windowEnd
        self.anchor = anchor
        self.until = until
    }

    // MARK: Convenience constructors

    public static func daily(at time: TimeOfDay, every days: Int = 1, startingOn anchor: Date = Date()) -> Recurrence {
        Recurrence(frequency: .daily, time: time, every: days, anchor: anchor)
    }

    public static func weekly(at time: TimeOfDay, on weekdays: Set<Int>) -> Recurrence {
        Recurrence(frequency: .weekly, time: time, weekdays: weekdays)
    }

    public static func monthly(at time: TimeOfDay, day: Int) -> Recurrence {
        Recurrence(frequency: .monthly, time: time, dayOfMonth: day)
    }

    public static func yearly(at time: TimeOfDay, month: Int, day: Int) -> Recurrence {
        Recurrence(frequency: .yearly, time: time, dayOfMonth: day, month: month)
    }

    public static func interval(minutes: Int, firstAt anchor: Date) -> Recurrence {
        Recurrence(frequency: .interval, every: minutes, anchor: anchor)
    }

    public static func interval(minutes: Int, from start: TimeOfDay, to end: TimeOfDay, on weekdays: Set<Int> = []) -> Recurrence {
        Recurrence(frequency: .interval, time: start, every: minutes, weekdays: weekdays, windowEnd: end)
    }

    // MARK: Next occurrence

    /// The first ring strictly after `date`, or nil when the rule has run out.
    public func next(after date: Date, calendar: Calendar) -> Date? {
        guard let candidate = rawNext(after: date, calendar: calendar) else { return nil }
        if let until {
            let limit = calendar.addingDays(1, to: calendar.startOfDay(for: until))
            if candidate >= limit { return nil }
        }
        return candidate
    }

    private func rawNext(after date: Date, calendar cal: Calendar) -> Date? {
        switch frequency {
        case .daily: return nextDaily(after: date, cal)
        case .weekly: return nextWeekly(after: date, cal)
        case .monthly: return nextMonthly(after: date, cal)
        case .yearly: return nextYearly(after: date, cal)
        case .interval: return windowEnd == nil ? nextOpenInterval(after: date, cal) : nextWindowedInterval(after: date, cal)
        }
    }

    private func nextDaily(after date: Date, _ cal: Calendar) -> Date? {
        let step = max(1, every)
        let anchorDay = cal.startOfDay(for: anchor)
        var day = max(cal.startOfDay(for: date), anchorDay)
        let offset = cal.dateComponents([.day], from: anchorDay, to: day).day ?? 0
        let remainder = offset % step
        if remainder != 0 { day = cal.addingDays(step - remainder, to: day) }
        for _ in 0..<3 {
            if let c = time.on(day, calendar: cal), c > date { return c }
            day = cal.addingDays(step, to: day)
        }
        return nil
    }

    private func nextWeekly(after date: Date, _ cal: Calendar) -> Date? {
        let days = weekdays.isEmpty ? Weekday.everyDay : weekdays
        let start = cal.startOfDay(for: date)
        for i in 0..<15 {
            let day = cal.addingDays(i, to: start)
            guard days.contains(cal.component(.weekday, from: day)) else { continue }
            if let c = time.on(day, calendar: cal), c > date { return c }
        }
        return nil
    }

    private func nextMonthly(after date: Date, _ cal: Calendar) -> Date? {
        let comps = cal.dateComponents([.year, .month], from: date)
        guard let firstOfMonth = cal.date(from: comps) else { return nil }
        for i in 0..<25 {
            guard let monthStart = cal.date(byAdding: .month, value: i, to: firstOfMonth),
                  let c = clampedDay(dayOfMonth, inMonthOf: monthStart, cal), c > date else { continue }
            return c
        }
        return nil
    }

    private func nextYearly(after date: Date, _ cal: Calendar) -> Date? {
        let year = cal.component(.year, from: date)
        for i in 0..<9 {
            var c = DateComponents()
            c.year = year + i
            c.month = min(max(month, 1), 12)
            c.day = 1
            guard let monthStart = cal.date(from: c),
                  let candidate = clampedDay(dayOfMonth, inMonthOf: monthStart, cal), candidate > date else { continue }
            return candidate
        }
        return nil
    }

    private func clampedDay(_ day: Int, inMonthOf monthStart: Date, _ cal: Calendar) -> Date? {
        let length = cal.range(of: .day, in: .month, for: monthStart)?.count ?? 28
        let d = min(max(day, 1), length)
        return time.on(cal.addingDays(d - 1, to: monthStart), calendar: cal)
    }

    private var stepSeconds: TimeInterval { TimeInterval(max(1, every) * 60) }

    private func nextOpenInterval(after date: Date, _ cal: Calendar) -> Date? {
        var after = date
        for _ in 0..<20 {
            let t: Date
            if after < anchor {
                t = anchor
            } else {
                let k = floor(after.timeIntervalSince(anchor) / stepSeconds) + 1
                t = anchor.addingTimeInterval(k * stepSeconds)
            }
            if weekdays.isEmpty || weekdays.contains(cal.component(.weekday, from: t)) { return t }
            // Skip to just before the start of the next day and try again.
            after = cal.addingDays(1, to: cal.startOfDay(for: t)).addingTimeInterval(-1)
        }
        return nil
    }

    private func nextWindowedInterval(after date: Date, _ cal: Calendar) -> Date? {
        guard let windowEnd else { return nil }
        let today = cal.startOfDay(for: date)
        // Start one day back so a window that crosses midnight (22:00–02:00) is still found.
        for i in -1..<400 {
            let day = cal.addingDays(i, to: today)
            if !weekdays.isEmpty && !weekdays.contains(cal.component(.weekday, from: day)) { continue }
            guard let start = time.on(day, calendar: cal) else { continue }
            let endDay = windowEnd <= time ? cal.addingDays(1, to: day) : day
            guard let end = windowEnd.on(endDay, calendar: cal) else { continue }
            if date < start { return start }
            let k = floor(date.timeIntervalSince(start) / stepSeconds) + 1
            let t = start.addingTimeInterval(k * stepSeconds)
            if t <= end { return t }
        }
        return nil
    }
}
