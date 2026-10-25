import Foundation

/// Human-readable text for times, countdowns and repeat rules.
public enum Describe {
    public static func time(_ date: Date, calendar: Calendar) -> String {
        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = calendar.timeZone
        f.locale = calendar.locale ?? .current
        f.dateStyle = .none
        f.timeStyle = .short
        // ICU puts a narrow no-break space before AM/PM; plain spaces read the same and wrap better.
        return f.string(from: date).replacingOccurrences(of: "\u{202F}", with: " ")
    }

    public static func time(_ t: TimeOfDay, calendar: Calendar) -> String {
        let ref = t.on(calendar.startOfDay(for: Date(timeIntervalSince1970: 1_700_000_000)), calendar: calendar) ?? Date()
        return time(ref, calendar: calendar)
    }

    /// "Today at 5:00 PM", "Tomorrow at 7:15 AM", "Fri, Oct 30 at 9:00 AM", "Mar 3, 2027 at 8:00 AM".
    public static func when(_ date: Date, now: Date, calendar: Calendar) -> String {
        let t = time(date, calendar: calendar)
        let day = calendar.startOfDay(for: date)
        let today = calendar.startOfDay(for: now)
        let days = calendar.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case 0: return "Today at \(t)"
        case 1: return "Tomorrow at \(t)"
        case -1: return "Yesterday at \(t)"
        default:
            let f = DateFormatter()
            f.calendar = calendar
            f.timeZone = calendar.timeZone
            f.locale = calendar.locale ?? .current
            let sameYear = calendar.component(.year, from: date) == calendar.component(.year, from: now)
            f.setLocalizedDateFormatFromTemplate(days > 0 && days < 7 ? "EEEMMMd" : (sameYear ? "EEEMMMd" : "MMMdyyyy"))
            return "\(f.string(from: date)) at \(t)"
        }
    }

    /// "2h 13m", "45s", "3d 4h". Rounds up so "in 1m" never shows a past time.
    public static func countdown(from now: Date, to date: Date) -> String {
        let total = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        let d = total / 86_400, h = (total % 86_400) / 3_600, m = (total % 3_600) / 60, s = total % 60
        if d > 0 { return h > 0 ? "\(d)d \(h)h" : "\(d)d" }
        if h > 0 { return m > 0 ? "\(h)h \(m)m" : "\(h)h" }
        if m > 0 { return s > 0 && m < 5 ? "\(m)m \(s)s" : "\(m)m" }
        return "\(s)s"
    }

    /// "2:13:05" or "13:05" for the big countdown.
    public static func clock(from now: Date, to date: Date) -> String {
        let total = max(0, Int(date.timeIntervalSince(now).rounded(.up)))
        let h = total / 3_600, m = (total % 3_600) / 60, s = total % 60
        return h > 0 ? String(format: "%d:%02d:%02d", h, m, s) : String(format: "%d:%02d", m, s)
    }

    public static func minutes(_ n: Int) -> String {
        if n % 60 == 0 { return n == 60 ? "hour" : "\(n / 60) hours" }
        if n > 60 { return "\(n / 60) h \(n % 60) min" }
        return "\(n) min"
    }

    /// Weekday sets as people say them: "Weekdays", "Weekends", "Every day", "Mon, Wed, Fri".
    public static func weekdays(_ days: Set<Int>, calendar: Calendar, long: Bool = false) -> String {
        if days == Weekday.everyDay || days.isEmpty { return "Every day" }
        if days == Weekday.workdays { return "Weekdays" }
        if days == Weekday.weekend { return "Weekends" }
        let symbols = long ? calendar.weekdaySymbols : calendar.shortWeekdaySymbols
        let names = Weekday.displayOrder.filter(days.contains).map { symbols[$0 - 1] }
        if days.count == 1, let only = names.first { return long ? "Every \(only)" : only }
        return names.joined(separator: ", ")
    }

    /// The full sentence: "Weekdays at 7:15 AM", "Every 45 min, 10:00 AM–6:00 PM, weekdays".
    public static func recurrence(_ r: Recurrence, calendar: Calendar) -> String {
        let t = time(r.time, calendar: calendar)
        var text: String
        switch r.frequency {
        case .daily:
            text = r.every == 1 ? "Every day at \(t)" : (r.every == 2 ? "Every other day at \(t)" : "Every \(r.every) days at \(t)")
        case .weekly:
            text = "\(weekdays(r.weekdays, calendar: calendar, long: r.weekdays.count == 1)) at \(t)"
        case .monthly:
            text = r.dayOfMonth >= 31 ? "Last day of every month at \(t)" : "Monthly on the \(ordinal(r.dayOfMonth, calendar)) at \(t)"
        case .yearly:
            text = "Every year on \(monthDay(r.month, r.dayOfMonth, calendar)) at \(t)"
        case .interval:
            text = "Every \(minutes(r.every))"
            if let end = r.windowEnd {
                text += ", \(t)–\(time(end, calendar: calendar))"
            }
            if !r.weekdays.isEmpty && r.weekdays != Weekday.everyDay {
                text += ", " + weekdays(r.weekdays, calendar: calendar).lowercased()
            }
        }
        if let until = r.until {
            text += " until " + monthDay(calendar.component(.month, from: until), calendar.component(.day, from: until), calendar)
        }
        return text
    }

    /// The short chip text without the time: "Weekdays", "Every 45 min", "Monthly · 1st".
    public static func repeatChip(_ r: Recurrence, calendar: Calendar) -> String {
        switch r.frequency {
        case .daily: return r.every == 1 ? "Every day" : (r.every == 2 ? "Every other day" : "Every \(r.every) days")
        case .weekly: return weekdays(r.weekdays, calendar: calendar)
        case .monthly: return r.dayOfMonth >= 31 ? "Monthly · last day" : "Monthly · \(ordinal(r.dayOfMonth, calendar))"
        case .yearly: return "Yearly · \(monthDay(r.month, r.dayOfMonth, calendar))"
        case .interval: return "Every \(minutes(r.every))"
        }
    }

    public static func schedule(_ alarm: Alarm, now: Date, calendar: Calendar) -> String {
        switch alarm.schedule {
        case .once(let date): return when(date, now: now, calendar: calendar)
        case .repeating(let r): return recurrence(r, calendar: calendar)
        }
    }

    static func ordinal(_ n: Int, _ calendar: Calendar) -> String {
        let f = NumberFormatter()
        f.numberStyle = .ordinal
        f.locale = calendar.locale ?? .current
        return f.string(from: NSNumber(value: n)) ?? "\(n)"
    }

    static func monthDay(_ month: Int, _ day: Int, _ calendar: Calendar) -> String {
        let symbols = calendar.shortMonthSymbols
        let name = symbols[(min(max(month, 1), 12)) - 1]
        return "\(name) \(day)"
    }
}
