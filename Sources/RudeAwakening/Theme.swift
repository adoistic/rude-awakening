import AlarmCore
import SwiftUI

enum Theme {
    static let hot = Color(red: 0.86, green: 0.13, blue: 0.40)       // #DB2166
    static let ember = Color(red: 0.90, green: 0.30, blue: 0.08)     // #E64D14
    static let sun = Color(red: 1.0, green: 0.78, blue: 0.10)
    static let grape = Color(red: 0.45, green: 0.25, blue: 0.95)

    static let hero = LinearGradient(colors: [hot, ember], startPoint: .topLeading, endPoint: .bottomTrailing)
    static let brand = LinearGradient(colors: [hot, ember, sun], startPoint: .topLeading, endPoint: .bottomTrailing)

    static func display(_ size: CGFloat, _ weight: Font.Weight = .heavy) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }

    static let card = RoundedRectangle(cornerRadius: 18, style: .continuous)
}

/// The cheek, all in one place.
enum Cheek {
    static func pick(_ list: [String]) -> String { list.randomElement() ?? "" }

    static let taglines = [
        "Loud alarms for people who ignore polite ones.",
        "Your phone's chime is a lullaby. I am not.",
        "Type it. Forget it. Get yelled at.",
        "Your Mac, but with opinions.",
        "Snooze responsibly. Or don't. I'll know.",
    ]

    static let examples = [
        "in 20 minutes",
        "5 pm today: call mom",
        "every weekday at 7:15, gym, use the goose",
        "tomorrow 6am, flight to Dubai, be brutal",
        "every 45 min from 10 to 6 on weekdays: stand up",
        "1st of every month at 10: pay rent",
    ]

    static let placeholders = [
        "Tell me when to yell at you…",
        "“wake me in 25 minutes”",
        "“5 pm today, call mom”",
        "“every weekday at 7:15 for gym”",
        "“tomorrow 6am, I have a flight, be brutal”",
    ]

    static let thinking = [
        "Consulting the oracle…",
        "Doing clock maths…",
        "Asking a goose…",
        "Sharpening the air horn…",
        "Reading your mind. It's messy in there…",
    ]

    static let empty = [
        "Nothing scheduled. Suspiciously peaceful.",
        "Zero alarms. Who are you, a cat?",
        "No alarms. Enjoy the silence while it lasts.",
    ]

    static let taunts = [
        "The bed is lying to you.",
        "Snooze is a trap and you know it.",
        "Up. Up. UP. UPPPP.",
        "You set me. This is on you.",
        "Your future self is begging you.",
        "I can do this all day. Can you?",
        "Rise and shine. Mostly rise.",
        "This is not a drill. It is, however, an alarm.",
        "Every second you wait, a goose gets angrier.",
        "Coffee won't make itself. Neither will your life.",
    ]

    static let noReason = [
        "You didn't say why. Mysterious. Get up anyway.",
        "No reason given. Just vibes. Loud vibes.",
        "Past you wanted this. Don't ask questions.",
    ]

    static let volumeFights = [
        "Nice try.",
        "Turning me down? Bold.",
        "Volume is a privilege, not a right.",
        "Back up it goes.",
        "I live here now.",
    ]

    static let wrongAnswer = [
        "Nope. Brain still asleep?",
        "Wrong. Try again, sleepyhead.",
        "Maths is hard at this hour, huh?",
        "Close. Not really. Again.",
    ]

    static let doneReplies = [
        "Done. I'll be loud.",
        "Set. Prepare to be startled.",
        "Locked in. Earplugs won't save you.",
    ]

    static let stopped = [
        "Alarm stopped. Proud of you. Mildly.",
        "You're up! Or you're very good at holding buttons in your sleep.",
        "Silenced. For now.",
    ]

    static func snoozed(until: String, labels: [String]) -> String {
        let what = labels.isEmpty ? "" : " for “\(labels.joined(separator: "”, “"))”"
        return "Snoozed\(what) till \(until). Classic coward move. 💤"
    }

    /// What the voice yells between blasts, built around what the alarm is for.
    static func spokenLines(labels: [String], time: String) -> [String] {
        let reason = labels.joined(separator: ", and ")
        if reason.isEmpty {
            return [
                "Hey! It's \(time). Get up!",
                "Up! Up! Up!",
                "I can do this all day.",
                "It's \(time). Rise and shine. Mostly rise.",
            ]
        }
        return [
            "Hey! It's \(time). \(reason)!",
            "\(reason). Now. Not later. Now.",
            "Up! It's time for: \(reason)!",
            "I will not stop until you deal with: \(reason).",
        ]
    }
}

/// The app's mark: a gradient rounded square with an alarm clock that wiggles now and then.
struct AppMark: View {
    var size: CGFloat = 44
    @State private var wiggle = false

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous).fill(Theme.brand)
            Image(systemName: "alarm.fill")
                .font(.system(size: size * 0.5, weight: .bold))
                .foregroundStyle(.white)
                .symbolEffect(.bounce, value: wiggle)
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.hot.opacity(0.35), radius: 8, y: 3)
        .task {
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6))
                wiggle.toggle()
            }
        }
        .accessibilityHidden(true)
    }
}

struct Chip: View {
    let text: String
    var systemImage: String?
    var tint: Color = .secondary

    var body: some View {
        HStack(spacing: 4) {
            if let systemImage { Image(systemName: systemImage) }
            Text(text).lineLimit(1)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(tint.opacity(0.13), in: Capsule())
        .foregroundStyle(tint)
    }
}

/// "7:15" and "AM" as separate pieces so the number can be huge and the suffix small.
struct ClockParts {
    let number: String
    let suffix: String?

    init(_ date: Date, calendar: Calendar = .autoupdatingCurrent) {
        let locale = calendar.locale ?? .current
        let template = DateFormatter.dateFormat(fromTemplate: "j", options: 0, locale: locale) ?? "h a"
        let f = DateFormatter()
        f.locale = locale
        f.timeZone = calendar.timeZone
        if template.contains("a") {
            f.dateFormat = "h:mm"
            number = f.string(from: date)
            f.dateFormat = "a"
            suffix = f.string(from: date)
        } else {
            f.dateFormat = "HH:mm"
            number = f.string(from: date)
            suffix = nil
        }
    }
}

struct BigClock: View {
    let date: Date
    var size: CGFloat = 40
    var weight: Font.Weight = .bold

    var body: some View {
        let parts = ClockParts(date)
        HStack(alignment: .firstTextBaseline, spacing: size * 0.08) {
            Text(parts.number).font(Theme.display(size, weight)).monospacedDigit()
            if let suffix = parts.suffix {
                Text(suffix).font(Theme.display(size * 0.42, .semibold)).opacity(0.7)
            }
        }
    }
}

struct SoundLabel: View {
    let soundID: String?
    @EnvironmentObject private var prefs: Prefs

    var body: some View {
        let id = soundID ?? prefs.defaultSound
        if let info = SoundLibrary.info(for: id) {
            Chip(text: "\(info.emoji) \(info.name)", tint: Theme.grape)
        } else {
            Chip(text: "🎵 \(id.hasPrefix("file:") ? String(id.dropFirst(5)) : id)", tint: Theme.grape)
        }
    }
}

extension Alarm {
    /// Small caps line above the time: "WEEKDAYS", "ONCE · TOMORROW", "EVERY 45 MIN".
    func caption(now: Date, calendar: Calendar) -> String {
        switch schedule {
        case .repeating(let r):
            var text = Describe.repeatChip(r, calendar: calendar)
            if r.frequency == .interval, let end = r.windowEnd {
                text += " · \(Describe.time(r.time, calendar: calendar))–\(Describe.time(end, calendar: calendar))"
            }
            return text.uppercased()
        case .once(let date):
            let when = Describe.when(date, now: now, calendar: calendar)
            let day = when.components(separatedBy: " at ").first ?? when
            return "ONCE · \(day.uppercased())"
        }
    }

    /// The time to show big: the next ring, or the scheduled time when it's off.
    func displayDate(calendar: Calendar) -> Date? {
        if let next = nextFire(calendar: calendar) { return next }
        switch schedule {
        case .once(let date): return date
        case .repeating(let r): return r.time.on(Date(), calendar: calendar)
        }
    }

    var displayLabel: String { label.isEmpty ? "Untitled yell" : label }
}
