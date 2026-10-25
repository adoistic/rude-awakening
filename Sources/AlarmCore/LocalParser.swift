import Foundation

/// A small offline brain for when there is no OpenRouter key or no internet.
/// It understands "in 20 minutes", "tomorrow at 7", "5pm call mom" and
/// "every weekday at 7:15". Anything fancier needs the language model.
public enum LocalParser {
    public static func parse(_ text: String, now: Date, calendar cal: Calendar) -> ResolvedPlan {
        var out = ResolvedPlan()
        let lower = text.lowercased()

        if let seconds = relativeSeconds(in: lower), seconds > 0 {
            let fire = now.addingTimeInterval(TimeInterval(seconds))
            out.alarms = [Alarm(label: label(from: text), schedule: .once(fire), createdAt: now, prompt: text)]
            out.reply = "Set. Offline brain did the maths, so be impressed."
            return out
        }

        if let rule = repeating(in: lower, now: now, cal: cal) {
            out.alarms = [Alarm(label: label(from: text), schedule: .repeating(rule), createdAt: now, prompt: text)]
            out.reply = "Repeating alarm set. I'll be annoying on schedule."
            return out
        }

        if let (date, hadDay) = detectedDate(in: text, now: now, cal: cal) {
            var fire = date
            if fire <= now {
                if hadDay {
                    out.problems.append("That's in the past. Even offline, I can't time travel.")
                    return out
                }
                fire = cal.addingDays(1, to: fire)
                out.notes.append("That time already passed today, so I set it for tomorrow.")
            }
            out.alarms = [Alarm(label: label(from: text), schedule: .once(fire), createdAt: now, prompt: text)]
            out.reply = "Done. Offline, but still loud."
            return out
        }

        // A bare "at 5" that Apple's detector ignores: the soonest upcoming 5 o'clock.
        if let time = clockTime(in: lower) {
            let meridiem = lower.range(of: #"\d\s*(am|pm|a\.m|p\.m)"#, options: .regularExpression) != nil
            let options = meridiem || time.hour >= 12 || time.hour == 0
                ? [time] : [time, TimeOfDay(hour: time.hour + 12, minute: time.minute)]
            let today = cal.startOfDay(for: now)
            let fire = options.compactMap { $0.on(today, calendar: cal) }.first { $0 > now }
                ?? options.first?.on(cal.addingDays(1, to: today), calendar: cal)
            if let fire {
                out.alarms = [Alarm(label: label(from: text), schedule: .once(fire), createdAt: now, prompt: text)]
                out.reply = "Done. Offline, but still loud."
                return out
            }
        }

        out.problems.append("My offline brain only gets simple stuff like “in 20 min” or “tomorrow at 7”. Add an OpenRouter key for the clever bits.")
        return out
    }

    // MARK: "in 1h 30m", "in an hour", "half an hour", "20 min"

    static func relativeSeconds(in text: String) -> Int? {
        var t = text
        t = t.replacingOccurrences(of: "half an hour", with: "30 minutes")
        t = t.replacingOccurrences(of: "half hour", with: "30 minutes")
        t = t.replacingOccurrences(of: "an hour and a half", with: "90 minutes")
        t = t.replacingOccurrences(of: "a quarter of an hour", with: "15 minutes")
        t = t.replacingOccurrences(of: #"\ban? (?=(hour|minute|min|day|sec))"#, with: "1 ", options: .regularExpression)

        let pattern = #"(\d+(?:\.\d+)?)\s*(seconds?|secs?|s|minutes?|mins?|m|hours?|hrs?|h|days?|d)\b"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(t.startIndex..., in: t)
        let matches = regex.matches(in: t, range: range)
        guard !matches.isEmpty else { return nil }

        // Only treat it as relative when it reads like a duration, not a clock time ("at 5 m"?).
        let looksRelative = t.contains("in ") || t.contains("after ") || t.contains("from now")
            || t.hasPrefix("nap") || matches.first.map({ $0.range.location == 0 }) == true
            || t.range(of: #"^\s*(set (an )?alarm|alarm|timer|wake me( up)?|remind me)\s*(for|in)?\s*\d"#, options: .regularExpression) != nil
        guard looksRelative, !t.contains(" at ") else { return nil }

        var total = 0.0
        for m in matches {
            guard let nr = Range(m.range(at: 1), in: t), let ur = Range(m.range(at: 2), in: t),
                  let n = Double(t[nr]) else { continue }
            switch t[ur].first {
            case "s": total += n
            case "m": total += n * 60
            case "h": total += n * 3_600
            case "d": total += n * 86_400
            default: break
            }
        }
        return total > 0 ? Int(total.rounded()) : nil
    }

    // MARK: "every day at 7", "weekdays at 7:15", "every monday at 9"

    static func repeating(in text: String, now: Date, cal: Calendar) -> Recurrence? {
        let days: Set<Int>?
        if text.contains("weekday") || text.contains("work day") || text.contains("workday") {
            days = Weekday.workdays
        } else if text.contains("weekend") {
            days = Weekday.weekend
        } else if text.contains("every day") || text.contains("everyday") || text.contains("daily") || text.contains("each day") {
            days = Weekday.everyDay
        } else if text.contains("every ") {
            let names = ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday"]
            let found = Set(names.enumerated().filter { text.contains($0.element) || text.contains(String($0.element.prefix(3)) + " ") }.map { $0.offset + 1 })
            days = found.isEmpty ? nil : found
        } else {
            days = nil
        }
        guard let days, let time = clockTime(in: text) else { return nil }
        return days == Weekday.everyDay ? .daily(at: time, startingOn: cal.startOfDay(for: now)) : .weekly(at: time, on: days)
    }

    /// "7", "7:15", "7pm", "19:30", "7.15 am", "noon", "midnight".
    static func clockTime(in text: String) -> TimeOfDay? {
        if text.contains("noon") { return TimeOfDay(hour: 12, minute: 0) }
        if text.contains("midnight") { return TimeOfDay(hour: 0, minute: 0) }
        let pattern = #"(?:at\s+)?\b(\d{1,2})(?:[:.](\d{2}))?\s*(am|pm|a\.m\.|p\.m\.)?"#
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        for m in regex.matches(in: text, range: range) {
            guard let hr = Range(m.range(at: 1), in: text), var h = Int(text[hr]) else { continue }
            let minute = Range(m.range(at: 2), in: text).flatMap { Int(text[$0]) } ?? 0
            let suffix = Range(m.range(at: 3), in: text).map { String(text[$0]) }
            let hasAt = text[Range(m.range, in: text)!].hasPrefix("at")
            guard suffix != nil || m.range(at: 2).location != NSNotFound || hasAt else { continue }
            guard h <= 23, minute <= 59 else { continue }
            if let suffix {
                if suffix.hasPrefix("p") && h < 12 { h += 12 }
                if suffix.hasPrefix("a") && h == 12 { h = 0 }
            }
            return TimeOfDay(hour: h, minute: minute)
        }
        return nil
    }

    // MARK: Apple's own date detector for "tomorrow at 5pm", "Friday 9am", "Dec 25 at 8"

    static func detectedDate(in text: String, now: Date, cal: Calendar) -> (Date, Bool)? {
        guard let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.date.rawValue) else { return nil }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = detector.firstMatch(in: text, range: range), let date = match.date else { return nil }
        let phrase = Range(match.range, in: text).map { text[$0].lowercased() } ?? ""
        let dayWords = ["tomorrow", "mon", "tue", "wed", "thu", "fri", "sat", "sun", "jan", "feb", "mar", "apr", "may",
                        "jun", "jul", "aug", "sep", "oct", "nov", "dec", "/", "next"]
        let hadDay = dayWords.contains { phrase.contains($0) }
        // Without am/pm the detector guesses ("tomorrow at 7" becomes 7 PM). Use the same rule
        // as the model prompt instead: whichever of the two is soonest in the future.
        var fire = date
        let explicit = phrase.contains("am") || phrase.contains("pm") || phrase.contains("a.m") || phrase.contains("p.m")
            || phrase.contains("noon") || phrase.contains("midnight")
            || phrase.range(of: #"\b(1[3-9]|2[0-3]|00)[:.]\d{2}"#, options: .regularExpression) != nil
        if !explicit {
            let hour = cal.component(.hour, from: date) % 12
            let minute = cal.component(.minute, from: date)
            let day = cal.startOfDay(for: date)
            let options = [TimeOfDay(hour: hour, minute: minute), TimeOfDay(hour: hour + 12, minute: minute)]
                .compactMap { $0.on(day, calendar: cal) }
            if let soonest = options.first(where: { $0 > now }) {
                fire = soonest
            } else if !hadDay, let morning = options.first {
                fire = cal.addingDays(1, to: morning)
            }
        }
        return (fire, hadDay)
    }

    // MARK: Labels

    /// What is left after removing the time phrases and filler: "5pm call mom" → "Call mom".
    static func label(from text: String) -> String {
        var t = " " + text.lowercased() + " "
        let patterns = [
            #"\b(set|make|create|add)\s+(an?\s+)?(alarm|reminder|timer)\b"#,
            #"\b(wake me( up)?|remind me( to)?|alarm|timer|ping me|yell at me)\b"#,
            #"\b(in|after)\s+\d+(\.\d+)?\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?|[smhd])\b"#,
            #"\b\d+(\.\d+)?\s*(seconds?|secs?|minutes?|mins?|hours?|hrs?|days?)\b"#,
            #"\b(at\s+)?\d{1,2}([:.]\d{2})?\s*(am|pm|a\.m\.|p\.m\.)?"#,
            #"\b(today|tonight|tomorrow|this (morning|evening|afternoon)|every ?day|daily|weekdays?|weekends?|every|from now|half an hour|an hour|noon|midnight)\b"#,
            #"\b(mon|tues|wednes|thurs|fri|satur|sun)day\b"#,
            #"\b(jan(uary)?|feb(ruary)?|mar(ch)?|apr(il)?|jun(e)?|jul(y)?|aug(ust)?|sep(t|tember)?|oct(ober)?|nov(ember)?|dec(ember)?)\b"#,
            #"\b\d{1,2}(st|nd|rd|th)\b"#,
            #"\b(on|at|for|to|in|the|and|please|me|up)\b"#,
            #"[,:;.!?\-–]+"#,
        ]
        for p in patterns {
            t = t.replacingOccurrences(of: p, with: " ", options: .regularExpression)
        }
        let words = t.split(whereSeparator: \.isWhitespace)
        guard !words.isEmpty else { return "" }
        let joined = words.prefix(6).joined(separator: " ")
        return joined.prefix(1).uppercased() + joined.dropFirst()
    }
}
