import Foundation

/// A wall-clock time without a date, such as 07:15.
public struct TimeOfDay: Codable, Hashable, Comparable, Sendable {
    public var hour: Int
    public var minute: Int

    public init(hour: Int, minute: Int) {
        self.hour = min(max(hour, 0), 23)
        self.minute = min(max(minute, 0), 59)
    }

    /// Parses 24-hour strings: "7:15", "07:15", "19:05", "07:15:00".
    public init?(string: String) {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: ":")
        guard parts.count >= 2,
              let h = Int(parts[0]), let m = Int(parts[1]),
              (0...24).contains(h), (0...59).contains(m) else { return nil }
        self.init(hour: h == 24 ? 0 : h, minute: m)
    }

    public init(date: Date, calendar: Calendar) {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        self.init(hour: c.hour ?? 0, minute: c.minute ?? 0)
    }

    public var minutesSinceMidnight: Int { hour * 60 + minute }
    public var string24: String { String(format: "%02d:%02d", hour, minute) }

    public static func < (a: TimeOfDay, b: TimeOfDay) -> Bool {
        a.minutesSinceMidnight < b.minutesSinceMidnight
    }

    /// This time on the given day, in the calendar's time zone.
    /// Times that fall into a daylight-saving gap move forward to the first valid instant.
    public func on(_ day: Date, calendar: Calendar) -> Date? {
        var c = calendar.dateComponents([.year, .month, .day], from: day)
        c.hour = hour
        c.minute = minute
        c.second = 0
        return calendar.date(from: c)
    }
}

/// Calendar weekday numbers, as Foundation uses them: 1 = Sunday … 7 = Saturday.
public enum Weekday {
    public static let codes = ["sun", "mon", "tue", "wed", "thu", "fri", "sat"]
    public static let workdays: Set<Int> = [2, 3, 4, 5, 6]
    public static let weekend: Set<Int> = [1, 7]
    public static let everyDay: Set<Int> = Set(1...7)
    /// Monday-first display order.
    public static let displayOrder = [2, 3, 4, 5, 6, 7, 1]

    public static func number(for code: String) -> Int? {
        let key = String(code.lowercased().prefix(3))
        return codes.firstIndex(of: key).map { $0 + 1 }
    }

    public static func code(for number: Int) -> String {
        codes[((number - 1) % 7 + 7) % 7]
    }
}

public extension Calendar {
    /// A Gregorian calendar fixed to one time zone, for tests and evals.
    static func fixed(timeZone: TimeZone, locale: Locale = Locale(identifier: "en_US")) -> Calendar {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = timeZone
        cal.locale = locale
        return cal
    }

    /// Parses "YYYY-MM-DD" into the start of that day.
    func day(fromISO string: String) -> Date? {
        let parts = string.trimmingCharacters(in: .whitespaces).split(separator: "-")
        guard parts.count == 3,
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]),
              (1...12).contains(m), (1...31).contains(d) else { return nil }
        var c = DateComponents()
        c.year = y
        c.month = m
        c.day = d
        c.hour = 12 // midday avoids DST edge cases; callers take startOfDay
        guard let date = self.date(from: c),
              component(.day, from: date) == d else { return nil }
        return startOfDay(for: date)
    }

    func isoDay(_ date: Date) -> String {
        let c = dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    func addingDays(_ n: Int, to date: Date) -> Date {
        self.date(byAdding: .day, value: n, to: date) ?? date.addingTimeInterval(Double(n) * 86_400)
    }
}
