import AlarmCore
import Foundation

/// Sentences people actually type, with what must come out, at a fixed "now":
/// Sunday 25 October 2026, 16:35 in Kolkata.
enum Evals {
    struct Case {
        let text: String
        /// For each expected alarm, the accepted first rings ("yyyy-MM-dd HH:mm", or with ":ss").
        var fires: [[String]] = []
        var repeats: Bool?
        var chip: String?
        var label: String?
        var sound: String?
        var deletes: Int?
        var withExisting = false
    }

    static let tz = TimeZone(identifier: "Asia/Kolkata")!
    static let calendar = Calendar.fixed(timeZone: tz)
    static let now: Date = {
        var c = DateComponents()
        c.year = 2026; c.month = 10; c.day = 25; c.hour = 16; c.minute = 35; c.second = 0
        return calendar.date(from: c)!
    }()

    static let gymID = UUID(uuidString: "A1B2C3D4-0000-4000-8000-000000000001")!
    static let momID = UUID(uuidString: "B2C3D4E5-0000-4000-8000-000000000002")!

    static var existing: [Alarm] {
        var gym = Alarm(id: gymID, label: "Gym", schedule: .repeating(.weekly(at: TimeOfDay(hour: 7, minute: 15), on: Weekday.workdays)), soundID: "goose", createdAt: now.addingTimeInterval(-86_400 * 3))
        gym.armedAt = gym.createdAt
        let mom = Alarm(id: momID, label: "Call mom", schedule: .once(now.addingTimeInterval(3_600 * 2)), createdAt: now.addingTimeInterval(-600))
        return [gym, mom]
    }

    static let cases: [Case] = [
        Case(text: "wake me up in 20 minutes", fires: [["2026-10-25 16:55"]], repeats: false),
        Case(text: "Set an alarm at 5 pm today", fires: [["2026-10-25 17:00"]], repeats: false),
        Case(text: "set an alarm in the next few hours at 5 pm today", fires: [["2026-10-25 17:00"]], repeats: false),
        Case(text: "in 2 hours and 15 minutes", fires: [["2026-10-25 18:50"]], repeats: false),
        Case(text: "tomorrow at 6:30am, flight to Dubai", fires: [["2026-10-26 06:30"]], repeats: false, label: "dubai"),
        Case(text: "at 5", fires: [["2026-10-25 17:00"]], repeats: false),
        Case(text: "at 4", fires: [["2026-10-26 04:00"]], repeats: false),
        Case(text: "on friday at 9am", fires: [["2026-10-30 09:00"]], repeats: false),
        Case(text: "next monday 8am", fires: [["2026-10-26 08:00", "2026-11-02 08:00"]], repeats: false),
        Case(text: "3 November at 10:30", fires: [["2026-11-03 10:30"]], repeats: false),
        Case(text: "christmas morning", fires: [["2026-12-25 08:00", "2026-12-25 07:00", "2026-12-25 09:00"]], repeats: false),
        Case(text: "tonight", fires: [["2026-10-25 21:00", "2026-10-25 20:00", "2026-10-25 22:00"]], repeats: false),
        Case(text: "half an hour", fires: [["2026-10-25 17:05"]], repeats: false),
        Case(text: "alarm in 90 seconds", fires: [["2026-10-25 16:36:30"]], repeats: false),
        Case(text: "दो घंटे बाद उठा देना", fires: [["2026-10-25 18:35"]], repeats: false),
        Case(text: "alarms at 6, 6:10 and 6:20 tomorrow", fires: [["2026-10-26 06:00"], ["2026-10-26 06:10"], ["2026-10-26 06:20"]]),
        Case(text: "every weekday at 7:15 for gym", fires: [["2026-10-26 07:15"]], repeats: true, chip: "Weekdays", label: "gym"),
        Case(text: "every day at 10pm take meds", fires: [["2026-10-25 22:00"]], repeats: true, chip: "Every day", label: "med"),
        Case(text: "weekends at 10 am, use the goose", fires: [["2026-10-31 10:00"]], repeats: true, chip: "Weekends", sound: "goose"),
        Case(text: "every day except sunday at 6:45", fires: [["2026-10-26 06:45"]], repeats: true, chip: "Mon, Tue, Wed, Thu, Fri, Sat"),
        Case(text: "remind me at 17:30 every tuesday and thursday", fires: [["2026-10-27 17:30"]], repeats: true, chip: "Tue, Thu"),
        Case(text: "every 45 minutes from 10am to 6pm on weekdays: stand up", fires: [["2026-10-26 10:00"]], repeats: true, chip: "Every 45 min", label: "stand"),
        Case(text: "every 2 hours", fires: [["2026-10-25 18:35"]], repeats: true, chip: "Every 2 hours"),
        Case(text: "1st of every month at noon, pay rent", fires: [["2026-11-01 12:00"]], repeats: true, chip: "Monthly · 1st", label: "rent"),
        Case(text: "every year on march 3 at 8am, birthday", fires: [["2027-03-03 08:00"]], repeats: true, chip: "Yearly · Mar 3"),
        Case(text: "every other day at 9am", fires: [["2026-10-26 09:00"]], repeats: true, chip: "Every other day"),
        Case(text: "wake me at 7 every day for the next 5 days", fires: [["2026-10-26 07:00"]], repeats: true),
        Case(text: "something brutal at 6am tomorrow", fires: [["2026-10-26 06:00"]], repeats: false, sound: "airhorn"),
        Case(text: "kill the gym alarm", deletes: 1, withExisting: true),
        Case(text: "move my gym alarm to 8", fires: [["2026-10-26 08:00"]], repeats: true, chip: "Weekdays", label: "gym", deletes: 1, withExisting: true),
        Case(text: "delete all my alarms", deletes: 2, withExisting: true),
    ]

    static func run(client: OpenRouterClient) async -> Int32 {
        print("Evaluating \(cases.count) cases on \(client.model) at \(Describe.when(now, now: now, calendar: calendar)) (Asia/Kolkata)\n")
        let started = Date()
        let results = await withTaskGroup(of: (Int, [String], String).self) { group in
            for (i, c) in cases.enumerated() {
                group.addTask { (i, await check(c, client: client), c.text) }
            }
            var out: [(Int, [String], String)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }
        }
        var passed = 0
        for (_, failures, text) in results {
            if failures.isEmpty {
                passed += 1
                print("✅ \(text)")
            } else {
                print("❌ \(text)")
                failures.forEach { print("     \($0)") }
            }
        }
        print("\n\(passed)/\(cases.count) passed in \(String(format: "%.0f", Date().timeIntervalSince(started)))s")
        return passed == cases.count ? 0 : 2
    }

    static func check(_ c: Case, client: OpenRouterClient) async -> [String] {
        let alarms = c.withExisting ? existing : []
        let plan: AlarmPlan
        do {
            plan = try await client.plan(for: c.text, systemPrompt: Prompt.system(now: now, calendar: calendar, existing: alarms))
        } catch {
            return ["request failed: \(error.localizedDescription)"]
        }
        let r = PlanResolver.resolve(plan, prompt: c.text, existing: alarms, now: now, calendar: calendar)
        var failures: [String] = r.problems.map { "problem: \($0)" }

        let f = DateFormatter()
        f.calendar = calendar
        f.timeZone = tz
        f.locale = Locale(identifier: "en_US_POSIX")

        if r.alarms.count != c.fires.count {
            failures.append("expected \(c.fires.count) alarm(s), got \(r.alarms.count)")
        }
        let got = r.alarms.compactMap { $0.nextFire(calendar: calendar) }.sorted()
        for (i, accepted) in c.fires.enumerated() where i < got.count {
            f.dateFormat = accepted[0].count > 16 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
            let s = f.string(from: got[i])
            if !accepted.contains(s) { failures.append("ring \(i + 1): got \(s), want \(accepted.joined(separator: " or "))") }
        }
        for a in r.alarms {
            if let want = c.repeats, want != !a.isOneOff { failures.append("repeats: got \(!a.isOneOff), want \(want)") }
            if let chip = c.chip {
                let have = a.recurrence.map { Describe.repeatChip($0, calendar: calendar) } ?? "once"
                if have != chip { failures.append("repeat: got “\(have)”, want “\(chip)”") }
            }
            if let label = c.label, !a.label.lowercased().contains(label) { failures.append("label: got “\(a.label)”, want it to mention “\(label)”") }
            if let sound = c.sound, a.soundID != sound { failures.append("sound: got \(a.soundID ?? "default"), want \(sound)") }
        }
        if let d = c.deletes, r.deleteIDs.count != d { failures.append("deletes: got \(r.deleteIDs.count), want \(d)") }
        if c.text.contains("gym"), c.deletes != nil, !r.deleteIDs.isEmpty, !r.deleteIDs.contains(gymID) {
            failures.append("deleted the wrong alarm")
        }
        if !failures.isEmpty { failures.append("reply: \(r.reply)") }
        return failures
    }
}
