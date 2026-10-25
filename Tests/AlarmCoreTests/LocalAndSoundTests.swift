import Foundation
import Testing
@testable import AlarmCore

@Suite struct LocalParserTests {
    @Test(arguments: [
        ("wake me in 20 minutes", 1_200),
        ("in 1h 30m", 5_400),
        ("in an hour", 3_600),
        ("half an hour", 1_800),
        ("alarm in 90 seconds", 90),
        ("nap 20 min", 1_200),
    ])
    func relative(_ text: String, _ seconds: Int) {
        #expect(LocalParser.relativeSeconds(in: text) == seconds)
    }

    @Test func clockTimes() {
        #expect(LocalParser.clockTime(in: "at 7pm") == TimeOfDay(hour: 19, minute: 0))
        #expect(LocalParser.clockTime(in: "7:15 am") == TimeOfDay(hour: 7, minute: 15))
        #expect(LocalParser.clockTime(in: "every day at 6") == TimeOfDay(hour: 6, minute: 0))
        #expect(LocalParser.clockTime(in: "12 am") == TimeOfDay(hour: 0, minute: 0))
    }

    @Test func weekdayRepeat() {
        let r = LocalParser.parse("every weekday at 7:15 gym", now: sunday, calendar: kolkata)
        #expect(r.alarms.first?.recurrence?.weekdays == Weekday.workdays)
        #expect(r.alarms.first?.label == "Gym")
    }

    @Test func labels() {
        #expect(LocalParser.label(from: "5pm call mom") == "Call mom")
        #expect(LocalParser.label(from: "wake me up in 20 minutes") == "")
        #expect(LocalParser.label(from: "remind me to drink water in 1 hour") == "Drink water")
    }
}

@Suite struct DescribeTests {
    @Test func countdowns() {
        #expect(Describe.countdown(from: sunday, to: sunday.addingTimeInterval(7_980)) == "2h 13m")
        #expect(Describe.countdown(from: sunday, to: sunday.addingTimeInterval(45)) == "45s")
        #expect(Describe.countdown(from: sunday, to: sunday.addingTimeInterval(86_400 * 3 + 3_600 * 4)) == "3d 4h")
        #expect(Describe.clock(from: sunday, to: sunday.addingTimeInterval(7_985)) == "2:13:05")
    }

    @Test func recurrenceText() {
        #expect(Describe.recurrence(.weekly(at: TimeOfDay(hour: 7, minute: 15), on: Weekday.workdays), calendar: kolkata) == "Weekdays at 7:15 AM")
        #expect(Describe.repeatChip(.weekly(at: TimeOfDay(hour: 7, minute: 15), on: [2, 4, 6]), calendar: kolkata) == "Mon, Wed, Fri")
        #expect(Describe.repeatChip(.monthly(at: TimeOfDay(hour: 12, minute: 0), day: 1), calendar: kolkata) == "Monthly · 1st")
        #expect(Describe.repeatChip(.interval(minutes: 90, firstAt: sunday), calendar: kolkata) == "Every 1 h 30 min")
    }

    @Test func when() {
        #expect(Describe.when(date("2026-10-25 17:00"), now: sunday, calendar: kolkata) == "Today at 5:00 PM")
        #expect(Describe.when(date("2026-10-26 07:00"), now: sunday, calendar: kolkata) == "Tomorrow at 7:00 AM")
    }
}

@Suite struct SoundTests {
    @Test(arguments: SoundLibrary.ids)
    func everySoundIsLoudAndClean(_ id: String) {
        let s = SoundSynth.render(id)
        let st = SoundSynth.stats(s)
        #expect(st.seconds > 1.5)
        #expect(st.peak <= 1.0)
        #expect(st.peak > 0.9)
        #expect(st.rmsDB > -24, "\(id) is too quiet: \(st.rmsDB) dBFS")
        #expect(!s.contains { $0.isNaN })
    }

    @Test func wavHeader() {
        let data = SoundSynth.wav([0, 0.5, -0.5])
        #expect(data.count == 44 + 6)
        #expect(String(decoding: data.prefix(4), as: UTF8.self) == "RIFF")
    }
}
