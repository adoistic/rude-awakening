import Foundation

/// The instructions and JSON schema sent to the model with every sentence.
public enum Prompt {
    public static func system(now: Date, calendar cal: Calendar, existing: [Alarm]) -> String {
        let en = Locale(identifier: "en_US_POSIX")
        let stamp = DateFormatter()
        stamp.calendar = cal
        stamp.timeZone = cal.timeZone
        stamp.locale = en
        stamp.dateFormat = "EEEE d MMMM yyyy, HH:mm:ss"

        let weekdayName = DateFormatter()
        weekdayName.calendar = cal
        weekdayName.timeZone = cal.timeZone
        weekdayName.locale = en
        weekdayName.dateFormat = "EEEE"

        let tz = cal.timeZone
        let offset = tz.secondsFromGMT(for: now)
        let offsetText = String(format: "UTC%@%02d:%02d", offset < 0 ? "-" : "+", abs(offset) / 3600, (abs(offset) % 3600) / 60)

        let today = cal.startOfDay(for: now)
        var days: [String] = []
        for i in 0..<22 {
            let d = cal.addingDays(i, to: today)
            var line = "- \(cal.isoDay(d)) \(weekdayName.string(from: d))"
            if i == 0 { line += " (today)" }
            if i == 1 { line += " (tomorrow)" }
            days.append(line)
        }

        let posix = Calendar.fixed(timeZone: cal.timeZone, locale: en)
        let alarmLines: [String] = existing.map { a in
            let label = a.label.isEmpty ? "(no label)" : "\"\(a.label)\""
            let state = a.isEnabled ? (a.isFinished ? "finished" : "on") : "off"
            var line = "- id \(a.shortID): \(label), \(Describe.schedule(a, now: now, calendar: posix)), \(state)"
            if let next = a.nextFire(calendar: cal) {
                line += ", next \(cal.isoDay(next)) \(TimeOfDay(date: next, calendar: cal).string24)"
            }
            if let s = a.soundID { line += ", sound \(s)" }
            return line
        }

        let sounds = SoundLibrary.all.map { "- \($0.id): \($0.name) (\($0.vibe))" }

        // A worked example of the "no am/pm" rule, using the real current time.
        let hour = cal.component(.hour, from: now)
        let soon = (hour % 12) + 1                       // the next o'clock on a 12-hour face
        let soonIsAhead = TimeOfDay(hour: hour + 1 <= 23 ? hour + 1 : 0, minute: 0)
        let ampmExample = "Right now \"at \(soon)\" means \(soonIsAhead.string24) \(hour + 1 <= 23 ? "today" : "tomorrow")."

        return """
        You are the scheduling brain of "Rude Awakening", a loud, cheeky alarm clock for macOS. \
        The user types what they want in plain language (any language, typos welcome). \
        You turn it into alarm instructions as JSON. The app does the date maths and the ringing; \
        you only decide what the user meant.

        NOW
        - Local date and time: \(stamp.string(from: now))
        - Time zone: \(tz.identifier) (\(offsetText))
        - The Mac's clock is the truth. Today is \(cal.isoDay(today)).

        UPCOMING DAYS (read weekdays from this list, never work them out yourself)
        \(days.joined(separator: "\n"))

        EXISTING ALARMS
        \(alarmLines.isEmpty ? "- none" : alarmLines.joined(separator: "\n"))

        SOUNDS (ids for the "sound" field)
        \(sounds.joined(separator: "\n"))

        HOW TO FILL EACH ALARM
        kind "relative": a duration from now ("in 20 minutes", "2 hours from now", "nap 20", "half an hour"). \
        Put it in offset_days / offset_hours / offset_minutes / offset_seconds. Never turn it into a clock time.
        kind "once": one ring at a clock time ("at 5 pm", "tomorrow 6am", "on Friday at 9", "Dec 25 at 8"). \
        date = YYYY-MM-DD, time = HH:MM in 24-hour time.
          - No date given: today if that time is still ahead of now, otherwise tomorrow.
          - No am/pm: let the context decide first ("wake me up at 7", "gym at 6" before work = morning; \
        "dinner at 7", "call at 9 tonight" = evening). Only when the context gives no hint, pick whichever \
        is soonest in the future. \(ampmExample)
          - A day but no time: morning 08:00, noon 12:00, afternoon 15:00, evening 19:00, tonight 21:00, \
        midnight 00:00 of the next day. Mention the time you picked in the reply.
          - "on Friday" or "next Friday": the soonest Friday after today, never today itself.
          - "in the next few hours at 5 pm today" just means 17:00 today.
        kind "repeat": anything that repeats. Set frequency:
          - "daily": time; every = days between rings (1 every day, 2 every other day); \
        date = first day only if the user names one.
          - "weekly": time; weekdays such as ["mon","wed","fri"]. Weekdays = mon to fri. \
        Weekends = sat and sun. "Every day except Sunday" = mon to sat.
          - "monthly": time; day_of_month 1 to 31 (31 = last day of the month).
          - "yearly": time; month 1 to 12; day_of_month.
          - "interval": every = MINUTES between rings (every 2 hours = 120). If it is limited to part \
        of the day ("from 9 to 5"), time = window start and window_end = window end. If there is a start \
        but no end ("every 2 hours starting at 9"), set time only. With neither, leave time empty and the \
        first ring is one interval from now. weekdays optionally limits the days ([] = every day).
          - until = YYYY-MM-DD of the last day it should ring, if the user gives an end \
        ("until Friday", "for the next 5 days"), else "".

        CHANGING EXISTING ALARMS
        - cancel / delete / kill / remove: their ids go in delete_ids. turn off / pause / mute: disable_ids. \
        turn on / resume: enable_ids.
        - "move my gym alarm to 8": delete the old id and create the new alarm with the same label, sound, \
        repeat and date (unless the user changes them). Say the day it lands on correctly in the reply.
        - "delete all alarms": every id.
        - Match alarms by label, time or description. If nothing matches, say so in the reply and change nothing.

        OTHER FIELDS
        - label: what the alarm is for, in the user's words, at most 6 words ("Call mom", "Flight to Dubai"). \
        "" if they didn't say. Don't invent one.
        - sound: a sound id if the user asks for a sound or a vibe ("use the goose", "something brutal"), else "". \
        "random" or "surprise me" = chaos.
        - Several alarms in one message ("at 6, 6:10 and 6:20") = one entry each.
        - Fields that don't apply: "" for text, 0 for numbers, [] for lists, "none" for frequency.
        - understood: false only if you really cannot tell what they want. Then alarms = [] and ask a short question in the reply.
        - reply: one short, cheeky, funny line (at most 20 words) about what you set, in the user's language. \
        Playful roasting is welcome; never be mean about anything sensitive. Don't list exact dates, the app shows them.

        Answer with the JSON object only.
        """
    }

    /// The response schema as JSON text. Written by hand so the key order is the order
    /// we want the model to think in (kind first, reply last).
    public static func schemaJSON() -> String {
        let soundEnum = ([""] + SoundLibrary.ids).map { "\"\($0)\"" }.joined(separator: ",")
        let itemKeys = ["kind", "label", "offset_days", "offset_hours", "offset_minutes", "offset_seconds",
                        "date", "time", "frequency", "every", "weekdays", "day_of_month", "month",
                        "window_end", "until", "sound"]
        let item = """
        {"type":"object","additionalProperties":false,"properties":{\
        "kind":{"type":"string","enum":["relative","once","repeat"]},\
        "label":{"type":"string"},\
        "offset_days":{"type":"integer"},\
        "offset_hours":{"type":"integer"},\
        "offset_minutes":{"type":"integer"},\
        "offset_seconds":{"type":"integer"},\
        "date":{"type":"string","description":"YYYY-MM-DD or empty"},\
        "time":{"type":"string","description":"HH:MM 24-hour or empty"},\
        "frequency":{"type":"string","enum":["none","daily","weekly","monthly","yearly","interval"]},\
        "every":{"type":"integer"},\
        "weekdays":{"type":"array","items":{"type":"string","enum":["mon","tue","wed","thu","fri","sat","sun"]}},\
        "day_of_month":{"type":"integer"},\
        "month":{"type":"integer"},\
        "window_end":{"type":"string","description":"HH:MM 24-hour or empty"},\
        "until":{"type":"string","description":"YYYY-MM-DD or empty"},\
        "sound":{"type":"string","enum":[\(soundEnum)]}\
        },"required":[\(itemKeys.map { "\"\($0)\"" }.joined(separator: ","))]}
        """
        let ids = "{\"type\":\"array\",\"items\":{\"type\":\"string\"}}"
        return """
        {"type":"object","additionalProperties":false,"properties":{\
        "understood":{"type":"boolean"},\
        "alarms":{"type":"array","items":\(item)},\
        "delete_ids":\(ids),\
        "disable_ids":\(ids),\
        "enable_ids":\(ids),\
        "reply":{"type":"string"}\
        },"required":["understood","alarms","delete_ids","disable_ids","enable_ids","reply"]}
        """
    }
}
