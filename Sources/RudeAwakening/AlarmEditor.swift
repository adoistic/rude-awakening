import AlarmCore
import SwiftUI

/// Setting or changing an alarm by hand, for people who distrust robots.
struct AlarmEditor: View {
    enum Kind: String, CaseIterable, Identifiable {
        case once = "Once", daily = "Every day", weekdays = "Weekdays", weekends = "Weekends",
             custom = "Pick days", everyN = "Every N days", monthly = "Monthly", yearly = "Yearly", interval = "Every N minutes"
        var id: String { rawValue }
    }

    let original: Alarm
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var player: AlarmPlayer
    @Environment(\.dismiss) private var dismiss

    @State private var label = ""
    @State private var kind = Kind.once
    @State private var onceDate = Date()
    @State private var time = Date()
    @State private var days: Set<Int> = Weekday.workdays
    @State private var everyDays = 2
    @State private var dayOfMonth = 1
    @State private var yearlyDate = Date()
    @State private var intervalMinutes = 60
    @State private var useWindow = false
    @State private var windowEnd = Date()
    @State private var hasUntil = false
    @State private var until = Date()
    @State private var soundID = ""

    private var isNew: Bool { !store.alarms.contains { $0.id == original.id } }
    private var cal: Calendar { store.calendar }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(isNew ? "New alarm" : "Edit alarm").font(Theme.display(22, .heavy))
                Spacer()
            }
            .padding([.horizontal, .top], 22)

            Form {
                TextField("What's it for?", text: $label, prompt: Text("Call mom, gym, flight…"))

                Picker("Repeat", selection: $kind) {
                    ForEach(Kind.allCases) { Text($0.rawValue).tag($0) }
                }

                switch kind {
                case .once:
                    DatePicker("When", selection: $onceDate, in: Date()..., displayedComponents: [.date, .hourAndMinute])
                case .daily, .weekdays, .weekends:
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                case .custom:
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    DayPicker(days: $days, calendar: cal)
                case .everyN:
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Stepper("Every \(everyDays) days", value: $everyDays, in: 2...30)
                case .monthly:
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                    Stepper(dayOfMonth >= 31 ? "On the last day" : "On day \(dayOfMonth)", value: $dayOfMonth, in: 1...31)
                case .yearly:
                    DatePicker("On", selection: $yearlyDate, displayedComponents: .date)
                    DatePicker("Time", selection: $time, displayedComponents: .hourAndMinute)
                case .interval:
                    Stepper("Every \(Describe.minutes(intervalMinutes))", value: $intervalMinutes, in: 5...720, step: 5)
                    Toggle("Only part of the day", isOn: $useWindow)
                    if useWindow {
                        DatePicker("From", selection: $time, displayedComponents: .hourAndMinute)
                        DatePicker("Until", selection: $windowEnd, displayedComponents: .hourAndMinute)
                        DayPicker(days: $days, calendar: cal)
                    }
                }

                if kind != .once {
                    Toggle("Stop repeating after a date", isOn: $hasUntil)
                    if hasUntil { DatePicker("Last day", selection: $until, in: Date()..., displayedComponents: .date) }
                }

                Picker("Sound", selection: $soundID) {
                    Text("Default").tag("")
                    ForEach(SoundLibrary.all) { Text("\($0.emoji) \($0.name)").tag($0.id) }
                    ForEach(customSounds, id: \.self) { Text("🎵 \($0)").tag("file:\($0)") }
                }
                HStack {
                    Spacer()
                    Button(player.previewing == previewID ? "Stop preview" : "Preview sound", systemImage: player.previewing == previewID ? "stop.fill" : "play.fill") {
                        player.togglePreview(previewID)
                    }
                }
            }
            .formStyle(.grouped)

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        store.delete(original.id)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { player.stopPreview(); dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Set alarm" : "Save") {
                    player.stopPreview()
                    store.upsert(build())
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .tint(Theme.hot)
                .disabled(kind == .custom && days.isEmpty)
            }
            .padding(18)
        }
        .frame(width: 480)
        .frame(minHeight: 400)
        .onAppear(perform: load)
    }

    private var previewID: String { soundID.isEmpty ? Prefs.shared.defaultSound : soundID }

    private var customSounds: [String] {
        (try? FileManager.default.contentsOfDirectory(atPath: AppPaths.sounds.path))?.filter { !$0.hasPrefix(".") }.sorted() ?? []
    }

    private func load() {
        label = original.label
        soundID = original.soundID ?? ""
        switch original.schedule {
        case .once(let d):
            kind = .once
            onceDate = max(d, Date().addingTimeInterval(60))
            time = d
        case .repeating(let r):
            time = r.time.on(Date(), calendar: cal) ?? Date()
            days = r.weekdays.isEmpty ? Weekday.workdays : r.weekdays
            hasUntil = r.until != nil
            until = r.until ?? Date()
            switch r.frequency {
            case .daily: kind = r.every == 1 ? .daily : .everyN; everyDays = max(2, r.every)
            case .weekly:
                kind = r.weekdays == Weekday.workdays ? .weekdays : r.weekdays == Weekday.weekend ? .weekends : r.weekdays == Weekday.everyDay ? .daily : .custom
            case .monthly: kind = .monthly; dayOfMonth = r.dayOfMonth
            case .yearly:
                kind = .yearly
                var c = DateComponents()
                c.year = cal.component(.year, from: Date()); c.month = r.month; c.day = r.dayOfMonth
                yearlyDate = cal.date(from: c) ?? Date()
            case .interval:
                kind = .interval
                intervalMinutes = r.every
                useWindow = r.windowEnd != nil
                if let end = r.windowEnd { windowEnd = end.on(Date(), calendar: cal) ?? Date() }
                if r.windowEnd == nil { days = [] }
            }
        }
    }

    private func build() -> Alarm {
        var a = original
        a.label = label.trimmed
        a.soundID = soundID.isEmpty ? nil : soundID
        let t = TimeOfDay(date: time, calendar: cal)
        var rule: Recurrence?
        switch kind {
        case .once:
            a.schedule = .once(onceDate)
        case .daily:
            rule = .daily(at: t, startingOn: cal.startOfDay(for: Date()))
        case .weekdays:
            rule = .weekly(at: t, on: Weekday.workdays)
        case .weekends:
            rule = .weekly(at: t, on: Weekday.weekend)
        case .custom:
            rule = .weekly(at: t, on: days)
        case .everyN:
            let today = cal.startOfDay(for: Date())
            let first = (t.on(today, calendar: cal) ?? Date()) > Date() ? today : cal.addingDays(1, to: today)
            rule = .daily(at: t, every: everyDays, startingOn: first)
        case .monthly:
            rule = .monthly(at: t, day: dayOfMonth)
        case .yearly:
            rule = .yearly(at: t, month: cal.component(.month, from: yearlyDate), day: cal.component(.day, from: yearlyDate))
        case .interval:
            if useWindow {
                rule = .interval(minutes: intervalMinutes, from: t, to: TimeOfDay(date: windowEnd, calendar: cal), on: days == Weekday.everyDay ? [] : days)
            } else {
                rule = .interval(minutes: intervalMinutes, firstAt: Date().addingTimeInterval(Double(intervalMinutes * 60)))
            }
        }
        if var rule {
            rule.until = hasUntil ? cal.startOfDay(for: until) : nil
            a.schedule = .repeating(rule)
        }
        return a
    }
}

struct DayPicker: View {
    @Binding var days: Set<Int>
    let calendar: Calendar

    var body: some View {
        HStack(spacing: 6) {
            ForEach(Weekday.displayOrder, id: \.self) { day in
                let on = days.contains(day)
                Button {
                    if on { days.remove(day) } else { days.insert(day) }
                } label: {
                    Text(String(calendar.veryShortWeekdaySymbols[day - 1]))
                        .font(.callout.weight(.bold))
                        .frame(width: 30, height: 30)
                        .background(on ? AnyShapeStyle(Theme.hero) : AnyShapeStyle(.quaternary), in: Circle())
                        .foregroundStyle(on ? .white : .primary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(calendar.weekdaySymbols[day - 1])
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}
