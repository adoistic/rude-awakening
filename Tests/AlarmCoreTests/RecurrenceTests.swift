import Foundation
import Testing
@testable import AlarmCore

let kolkata = Calendar.fixed(timeZone: TimeZone(identifier: "Asia/Kolkata")!)
let newYork = Calendar.fixed(timeZone: TimeZone(identifier: "America/New_York")!)

func date(_ s: String, _ cal: Calendar = kolkata) -> Date {
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = cal.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = s.count > 16 ? "yyyy-MM-dd HH:mm:ss" : "yyyy-MM-dd HH:mm"
    return f.date(from: s)!
}

func stamp(_ d: Date?, _ cal: Calendar = kolkata) -> String {
    guard let d else { return "nil" }
    let f = DateFormatter()
    f.calendar = cal
    f.timeZone = cal.timeZone
    f.locale = Locale(identifier: "en_US_POSIX")
    f.dateFormat = "yyyy-MM-dd HH:mm"
    return f.string(from: d)
}

// Sunday 25 October 2026, 16:35.
let sunday = date("2026-10-25 16:35")

@Suite struct RecurrenceTests {
    @Test func dailyLaterToday() {
        let r = Recurrence.daily(at: TimeOfDay(hour: 22, minute: 0), startingOn: sunday)
        #expect(stamp(r.next(after: sunday, calendar: kolkata)) == "2026-10-25 22:00")
    }

    @Test func dailyAlreadyPassedRollsToTomorrow() {
        let r = Recurrence.daily(at: TimeOfDay(hour: 7, minute: 0), startingOn: sunday)
        #expect(stamp(r.next(after: sunday, calendar: kolkata)) == "2026-10-26 07:00")
    }

    @Test func everyOtherDayFollowsAnchor() {
        let r = Recurrence.daily(at: TimeOfDay(hour: 9, minute: 0), every: 2, startingOn: date("2026-10-26 00:00"))
        #expect(stamp(r.next(after: sunday, calendar: kolkata)) == "2026-10-26 09:00")
        #expect(stamp(r.next(after: date("2026-10-26 09:00"), calendar: kolkata)) == "2026-10-28 09:00")
    }

    @Test func weekdaysSkipTheWeekend() {
        let r = Recurrence.weekly(at: TimeOfDay(hour: 7, minute: 15), on: Weekday.workdays)
        #expect(stamp(r.next(after: sunday, calendar: kolkata)) == "2026-10-26 07:15")
    }

    @Test func monthlyClampsToShortMonths() {
        let r = Recurrence.monthly(at: TimeOfDay(hour: 9, minute: 0), day: 31)
        #expect(stamp(r.next(after: date("2026-11-01 00:00"), calendar: kolkata)) == "2026-11-30 09:00")
        #expect(stamp(r.next(after: date("2027-02-01 00:00"), calendar: kolkata)) == "2027-02-28 09:00")
    }

    @Test func yearlyLeapDayClamps() {
        let r = Recurrence.yearly(at: TimeOfDay(hour: 8, minute: 0), month: 2, day: 29)
        #expect(stamp(r.next(after: sunday, calendar: kolkata)) == "2027-02-28 08:00")
        #expect(stamp(r.next(after: date("2027-12-31 00:00"), calendar: kolkata)) == "2028-02-29 08:00")
    }

    @Test func openIntervalStepsFromAnchor() {
        let r = Recurrence.interval(minutes: 30, firstAt: date("2026-10-25 17:05"))
        #expect(stamp(r.next(after: sunday, calendar: kolkata)) == "2026-10-25 17:05")
        #expect(stamp(r.next(after: date("2026-10-25 17:05"), calendar: kolkata)) == "2026-10-25 17:35")
        #expect(stamp(r.next(after: date("2026-10-25 18:00"), calendar: kolkata)) == "2026-10-25 18:05")
    }

    @Test func windowedIntervalOnWeekdays() {
        let r = Recurrence.interval(minutes: 45, from: TimeOfDay(hour: 10, minute: 0), to: TimeOfDay(hour: 18, minute: 0), on: Weekday.workdays)
        #expect(stamp(r.next(after: sunday, calendar: kolkata)) == "2026-10-26 10:00")
        #expect(stamp(r.next(after: date("2026-10-26 10:00"), calendar: kolkata)) == "2026-10-26 10:45")
        // 10:00 + 10×45 min = 17:30 is the last ring; the next is the following morning.
        #expect(stamp(r.next(after: date("2026-10-26 17:30"), calendar: kolkata)) == "2026-10-27 10:00")
    }

    @Test func windowAcrossMidnight() {
        let r = Recurrence.interval(minutes: 60, from: TimeOfDay(hour: 22, minute: 0), to: TimeOfDay(hour: 2, minute: 0))
        #expect(stamp(r.next(after: date("2026-10-26 00:30"), calendar: kolkata)) == "2026-10-26 01:00")
        #expect(stamp(r.next(after: date("2026-10-26 02:00"), calendar: kolkata)) == "2026-10-26 22:00")
    }

    @Test func untilStopsTheRule() {
        var r = Recurrence.daily(at: TimeOfDay(hour: 7, minute: 0), startingOn: sunday)
        r.until = date("2026-10-27 00:00")
        #expect(stamp(r.next(after: date("2026-10-26 08:00"), calendar: kolkata)) == "2026-10-27 07:00")
        #expect(r.next(after: date("2026-10-27 08:00"), calendar: kolkata) == nil)
    }

    @Test func wallClockSurvivesDST() {
        // US clocks go back on Sunday 1 November 2026.
        let r = Recurrence.daily(at: TimeOfDay(hour: 7, minute: 0), startingOn: date("2026-10-30 00:00", newYork))
        #expect(stamp(r.next(after: date("2026-10-31 08:00", newYork), calendar: newYork), newYork) == "2026-11-01 07:00")
        #expect(stamp(r.next(after: date("2026-11-01 08:00", newYork), calendar: newYork), newYork) == "2026-11-02 07:00")
    }

    @Test func springForwardGapMovesLater() {
        // 02:30 doesn't exist on 8 March 2026 in New York.
        let r = Recurrence.daily(at: TimeOfDay(hour: 2, minute: 30), startingOn: date("2026-03-07 00:00", newYork))
        let next = r.next(after: date("2026-03-07 12:00", newYork), calendar: newYork)
        #expect(next != nil)
        #expect(stamp(next, newYork).hasPrefix("2026-03-08 03"))
    }
}
