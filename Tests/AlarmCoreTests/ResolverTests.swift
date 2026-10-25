import Foundation
import Testing
@testable import AlarmCore

func item(_ build: (inout AlarmPlan.Item) -> Void) -> AlarmPlan.Item {
    var i = AlarmPlan.Item()
    build(&i)
    return i
}

func resolve(_ items: [AlarmPlan.Item], existing: [Alarm] = []) -> ResolvedPlan {
    var plan = AlarmPlan()
    plan.alarms = items
    return PlanResolver.resolve(plan, prompt: "test", existing: existing, now: sunday, calendar: kolkata)
}

@Suite struct ResolverTests {
    @Test func relativeUsesTheClockNotTheModel() {
        let r = resolve([item { $0.kind = "relative"; $0.offsetHours = 2; $0.offsetMinutes = 15 }])
        #expect(stamp(r.alarms.first?.nextFire(calendar: kolkata)) == "2026-10-25 18:50")
    }

    @Test func onceLaterToday() {
        let r = resolve([item { $0.kind = "once"; $0.time = "17:00" }])
        #expect(stamp(r.alarms.first?.onceDate) == "2026-10-25 17:00")
        #expect(r.notes.isEmpty)
    }

    @Test func passedTimeTodayMovesToTomorrowWithANote() {
        let r = resolve([item { $0.kind = "once"; $0.date = "2026-10-25"; $0.time = "09:00" }])
        #expect(stamp(r.alarms.first?.onceDate) == "2026-10-26 09:00")
        #expect(r.notes.count == 1)
    }

    @Test func explicitPastDateIsAProblem() {
        let r = resolve([item { $0.kind = "once"; $0.date = "2026-10-20"; $0.time = "09:00" }])
        #expect(r.alarms.isEmpty)
        #expect(r.problems.count == 1)
    }

    @Test func weeklyNeedsDays() {
        let ok = resolve([item { $0.kind = "repeat"; $0.frequency = "weekly"; $0.time = "07:15"; $0.weekdays = ["mon", "tue", "wed", "thu", "fri"] }])
        #expect(ok.alarms.first?.recurrence?.weekdays == Weekday.workdays)
        let bad = resolve([item { $0.kind = "repeat"; $0.frequency = "weekly"; $0.time = "07:15" }])
        #expect(bad.alarms.isEmpty)
    }

    @Test func dailyFirstRingIsNextOccurrence() {
        let r = resolve([item { $0.kind = "repeat"; $0.frequency = "daily"; $0.every = 2; $0.time = "09:00" }])
        #expect(stamp(r.alarms.first?.nextFire(calendar: kolkata)) == "2026-10-26 09:00")
    }

    @Test func openIntervalStartsOneIntervalFromNow() {
        let r = resolve([item { $0.kind = "repeat"; $0.frequency = "interval"; $0.every = 120 }])
        #expect(stamp(r.alarms.first?.nextFire(calendar: kolkata)) == "2026-10-25 18:35")
    }

    @Test func unknownSoundFallsBackToDefault() {
        let r = resolve([item { $0.kind = "relative"; $0.offsetMinutes = 5; $0.sound = "kitten" }])
        #expect(r.alarms.first?.soundID == nil)
        let g = resolve([item { $0.kind = "relative"; $0.offsetMinutes = 5; $0.sound = "goose" }])
        #expect(g.alarms.first?.soundID == "goose")
    }

    @Test func shortIDsMatchExistingAlarms() {
        let a = Alarm(label: "Gym", schedule: .once(sunday.addingTimeInterval(600)), createdAt: sunday)
        var plan = AlarmPlan()
        plan.deleteIDs = [a.shortID, "nope1234"]
        let r = PlanResolver.resolve(plan, prompt: "kill gym", existing: [a], now: sunday, calendar: kolkata)
        #expect(r.deleteIDs == [a.id])
    }

    @Test func sloppyJSONStillDecodes() throws {
        let text = """
        Sure! ```json
        {"understood": true, "alarms": [{"kind": "relative", "offset_minutes": "20", "offset_hours": null, "label": "Tea"}], "reply": "Steeping."}
        ```
        """
        let plan = try AlarmPlan.decode(fromModelText: text)
        #expect(plan.alarms.first?.offsetMinutes == 20)
        #expect(plan.alarms.first?.offsetHours == 0)
        #expect(plan.reply == "Steeping.")
    }

    @Test func schemaIsValidJSON() throws {
        let data = Data(Prompt.schemaJSON().utf8)
        let obj = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        #expect(obj?["type"] as? String == "object")
    }

    @Test func promptNamesToday() {
        let p = Prompt.system(now: sunday, calendar: kolkata, existing: [])
        #expect(p.contains("2026-10-25 Sunday (today)"))
        #expect(p.contains("2026-10-26 Monday (tomorrow)"))
        #expect(p.contains("\"at 5\" means 17:00 today"))
    }
}

@Suite struct EngineTests {
    @Test func oneOffRingsOnceThenFinishes() {
        var alarms = [Alarm(schedule: .once(date("2026-10-25 17:00")), createdAt: sunday)]
        #expect(AlarmEngine.tick(&alarms, now: date("2026-10-25 16:59"), calendar: kolkata).isEmpty)
        let r = AlarmEngine.tick(&alarms, now: date("2026-10-25 17:00:01"), calendar: kolkata)
        #expect(r.ring == [alarms[0].id])
        #expect(AlarmEngine.tick(&alarms, now: date("2026-10-25 17:00:02"), calendar: kolkata).isEmpty)
        AlarmEngine.dismiss(&alarms[0])
        #expect(!alarms[0].isEnabled)
    }

    @Test func snoozeRingsAgain() {
        var alarms = [Alarm(schedule: .once(date("2026-10-25 17:00")), createdAt: sunday)]
        _ = AlarmEngine.tick(&alarms, now: date("2026-10-25 17:00"), calendar: kolkata)
        AlarmEngine.snooze(&alarms[0], until: date("2026-10-25 17:09"))
        #expect(stamp(alarms[0].nextFire(calendar: kolkata)) == "2026-10-25 17:09")
        let r = AlarmEngine.tick(&alarms, now: date("2026-10-25 17:09"), calendar: kolkata)
        #expect(r.ring.count == 1)
    }

    @Test func repeatingSkipsToTheNextDayAfterRinging() {
        var alarms = [Alarm(schedule: .repeating(.daily(at: TimeOfDay(hour: 17, minute: 0), startingOn: sunday)), createdAt: sunday)]
        _ = AlarmEngine.tick(&alarms, now: date("2026-10-25 17:00"), calendar: kolkata)
        AlarmEngine.dismiss(&alarms[0])
        #expect(alarms[0].isEnabled)
        #expect(stamp(alarms[0].nextFire(calendar: kolkata)) == "2026-10-26 17:00")
    }

    @Test func sleepingThroughAnAlarmMarksItMissed() {
        var alarms = [Alarm(schedule: .once(date("2026-10-25 17:00")), createdAt: sunday)]
        let r = AlarmEngine.tick(&alarms, now: date("2026-10-25 19:30"), calendar: kolkata)
        #expect(r.ring.isEmpty)
        #expect(r.missed.count == 1)
        #expect(!alarms[0].isEnabled)
    }

    @Test func aDayAsleepRingsADailyAlarmAtMostOnce() {
        var alarms = [Alarm(schedule: .repeating(.daily(at: TimeOfDay(hour: 7, minute: 0), startingOn: sunday)), createdAt: sunday)]
        let r = AlarmEngine.tick(&alarms, now: date("2026-10-28 07:20"), calendar: kolkata)
        #expect(r.ring.count == 1)
        #expect(AlarmEngine.tick(&alarms, now: date("2026-10-28 07:21"), calendar: kolkata).isEmpty)
        #expect(stamp(alarms[0].nextFire(calendar: kolkata)) == "2026-10-29 07:00")
    }

    @Test func reEnablingAPastOneOffMovesItForward() {
        var a = Alarm(schedule: .once(date("2026-10-24 07:00")), createdAt: sunday)
        a.isEnabled = false
        AlarmEngine.enable(&a, now: sunday, calendar: kolkata)
        #expect(stamp(a.onceDate) == "2026-10-26 07:00")
    }
}
