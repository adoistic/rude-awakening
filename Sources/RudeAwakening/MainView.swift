import AlarmCore
import SwiftUI

struct MainView: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var prefs: Prefs
    @State private var text = ""
    @State private var showOnboarding = false
    @State private var tagline = Cheek.pick(Cheek.taglines)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                header
                HeroCard()
                VStack(alignment: .leading, spacing: 10) {
                    ExampleChips(text: $text)
                    CommandField(style: .large, text: $text)
                    if let outcome = store.outcome {
                        OutcomeCard(outcome: outcome).padding(.top, 4)
                    }
                    if let banner = store.banner {
                        Banner(text: banner) { store.banner = nil }
                    }
                }
                AlarmList()
            }
            .padding(.horizontal, 26)
            .padding(.top, 8)
            .padding(.bottom, 28)
            .animation(.snappy, value: store.outcome?.id)
            .animation(.snappy, value: store.alarms)
        }
        .scrollIndicators(.automatic)
        .frame(minWidth: 520, minHeight: 560)
        .background(Color(nsColor: .windowBackgroundColor).ignoresSafeArea())
        .sheet(item: $store.editing) { alarm in
            AlarmEditor(original: alarm).environmentObjects()
        }
        .sheet(isPresented: $showOnboarding) {
            OnboardingView { showOnboarding = false }.environmentObjects()
        }
        .onAppear {
            if !KeyStore.hasKey && !prefs.skippedOnboarding { showOnboarding = true }
        }
    }

    private var header: some View {
        HStack(spacing: 14) {
            AppMark(size: 46)
            VStack(alignment: .leading, spacing: 2) {
                Text("Rude Awakening").font(Theme.display(26, .black))
                Text(tagline).font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if !KeyStore.hasKey {
                Button { showOnboarding = true } label: {
                    Label("Add brain", systemImage: "brain.head.profile")
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.hot)
                .help("Add an OpenRouter key so I can understand sentences")
            }
            Button { WindowManager.shared.showSettings() } label: {
                Image(systemName: "gearshape.fill").font(.title3)
            }
            .buttonStyle(.borderless)
            .help("Settings (⌘,)")
            .accessibilityLabel("Settings")
        }
    }
}

/// "Ring in 2h 13m": the next alarm, big, on a hot gradient. Also proves we're on the Mac's clock.
struct HeroCard: View {
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var ticker: Ticker
    @EnvironmentObject private var prefs: Prefs

    var body: some View {
        let now = ticker.now
        Group {
            if let ringing = store.ringing {
                hero {
                    caption("RINGING RIGHT NOW")
                    Text(ringing.labels.first ?? "WAKE UP").font(Theme.display(40, .black)).lineLimit(2)
                    Button("Make it stop") { RingWindowManager.shared.show() }
                        .buttonStyle(.borderedProminent).tint(.white).foregroundStyle(Theme.hot)
                }
            } else if let next = store.nextUp {
                hero {
                    caption("RING IN")
                    Text(Describe.countdown(from: now, to: next.date))
                        .font(Theme.display(50, .black))
                        .monospacedDigit()
                        .contentTransition(.numericText(countsDown: true))
                        .animation(.snappy, value: Describe.countdown(from: now, to: next.date))
                    HStack(spacing: 6) {
                        Text(Describe.when(next.date, now: now, calendar: store.calendar)).fontWeight(.semibold)
                        Text("·")
                        Text(next.alarm.displayLabel).lineLimit(1)
                    }
                    .font(.title3)
                } trailing: {
                    let id = next.alarm.soundID ?? prefs.defaultSound
                    Text(SoundLibrary.info(for: id)?.emoji ?? "🎵")
                        .font(.system(size: 56))
                        .rotationEffect(.degrees(Double(Calendar.current.component(.second, from: now) % 2 == 0 ? -8 : 8)))
                        .animation(.spring(response: 0.25, dampingFraction: 0.3), value: Calendar.current.component(.second, from: now))
                        .accessibilityHidden(true)
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("😴").font(.system(size: 40)).accessibilityHidden(true)
                    Text(Cheek.empty[0]).font(Theme.display(22, .heavy))
                    Text("Type something below, like “wake me in 20 minutes”.").foregroundStyle(.secondary)
                    clockLine.foregroundStyle(.secondary)
                }
                .padding(22)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.background.secondary, in: Theme.card)
            }
        }
    }

    private var clockLine: some View {
        let tz = store.calendar.timeZone
        let city = tz.identifier.split(separator: "/").last.map { $0.replacingOccurrences(of: "_", with: " ") } ?? tz.identifier
        let offset = tz.localizedName(for: tz.isDaylightSavingTime(for: ticker.now) ? .shortDaylightSaving : .shortStandard, locale: .current) ?? ""
        return Label {
            Text("Mac clock: \(ticker.now.formatted(date: .abbreviated, time: .standard)) · \(city) time (\(offset))")
                .monospacedDigit()
        } icon: {
            Image(systemName: "clock")
        }
        .font(.caption)
    }

    private func caption(_ s: String) -> some View {
        Text(s).font(.caption.weight(.heavy)).tracking(1.5).opacity(0.9)
    }

    private func hero<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        hero(content, trailing: { EmptyView() })
    }

    private func hero<Content: View, Trailing: View>(@ViewBuilder _ content: () -> Content, @ViewBuilder trailing: () -> Trailing) -> some View {
        ZStack(alignment: .topTrailing) {
            // Big faint exclamation marks, like a cartoon alarm going off.
            Text("!!")
                .font(.system(size: 170, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.08))
                .rotationEffect(.degrees(12))
                .offset(x: 18, y: -40)
                .accessibilityHidden(true)
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    content()
                    clockLine.opacity(0.85).padding(.top, 4)
                }
                Spacer(minLength: 12)
                trailing()
            }
            .padding(22)
        }
        .foregroundStyle(.white)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.hero, in: Theme.card)
        .clipShape(Theme.card)
        .shadow(color: Theme.hot.opacity(0.3), radius: 14, y: 6)
    }
}

struct Banner: View {
    let text: String
    let dismiss: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "megaphone.fill").foregroundStyle(Theme.ember)
            Text(text).fixedSize(horizontal: false, vertical: true)
            Spacer()
            Button(action: dismiss) { Image(systemName: "xmark") }
                .buttonStyle(.borderless)
                .accessibilityLabel("Dismiss")
        }
        .font(.callout)
        .padding(12)
        .background(Theme.ember.opacity(0.1), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

struct AlarmList: View {
    @EnvironmentObject private var store: AlarmStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                sectionTitle("YOUR ALARMS", count: store.upcoming.count)
                Spacer()
                Button { store.newAlarm() } label: {
                    Label("Add by hand", systemImage: "plus")
                }
                .buttonStyle(.bordered)
                .keyboardShortcut("n", modifiers: .command)
            }
            if store.upcoming.isEmpty {
                Text("Nothing armed. Your mornings are dangerously unsupervised.")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 6)
            }
            ForEach(store.upcoming) { AlarmRow(alarm: $0) }

            if !store.paused.isEmpty {
                sectionTitle("SWITCHED OFF", count: store.paused.count).padding(.top, 8)
                ForEach(store.paused) { AlarmRow(alarm: $0) }
            }
            if !store.finished.isEmpty {
                HStack {
                    sectionTitle("DONE", count: store.finished.count)
                    Spacer()
                    Button("Clear") { store.clearFinished() }.buttonStyle(.borderless)
                }
                .padding(.top, 8)
                ForEach(store.finished) { AlarmRow(alarm: $0) }
            }
        }
    }

    private func sectionTitle(_ title: String, count: Int) -> some View {
        Text("\(title) · \(count)")
            .font(.caption.weight(.heavy))
            .tracking(1.2)
            .foregroundStyle(.secondary)
    }
}

/// Eight Sleep / WHOOP style: small caps repeat line, huge time, chips, a switch.
struct AlarmRow: View {
    let alarm: Alarm
    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var ticker: Ticker
    @State private var hovering = false

    var body: some View {
        let next = store.nextFire(alarm)
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 4) {
                Text(alarm.caption(now: ticker.now, calendar: store.calendar))
                    .font(.caption.weight(.bold)).tracking(1).foregroundStyle(.secondary)
                if let shown = alarm.displayDate(calendar: store.calendar) {
                    BigClock(date: shown, size: 38)
                }
                HStack(spacing: 6) {
                    Text(alarm.displayLabel).font(.headline).lineLimit(1)
                    SoundLabel(soundID: alarm.soundID)
                    if let next {
                        Chip(text: "in \(Describe.countdown(from: ticker.now, to: next))", systemImage: "timer", tint: Theme.hot)
                            .monospacedDigit()
                    }
                    if let snoozed = alarm.snoozedUntil {
                        Chip(text: "Snoozed till \(Describe.time(snoozed, calendar: store.calendar))", systemImage: "zzz", tint: .blue)
                    }
                }
            }
            Spacer(minLength: 8)
            if hovering {
                HStack(spacing: 2) {
                    iconButton("play.fill", "Test ring") { store.testRing(alarm) }
                    iconButton("pencil", "Edit") { store.editing = alarm }
                    iconButton("trash", "Delete") { store.delete(alarm.id) }
                }
                .transition(.opacity)
            }
            Toggle("On", isOn: Binding(get: { next != nil }, set: { store.setEnabled(alarm.id, $0) }))
                .toggleStyle(.switch)
                .labelsHidden()
                .tint(Theme.hot)
                .accessibilityLabel("\(alarm.displayLabel) on")
        }
        .padding(16)
        .background(.background.secondary, in: Theme.card)
        .overlay(Theme.card.strokeBorder(Color.primary.opacity(hovering ? 0.12 : 0.05)))
        .opacity(next == nil ? 0.6 : 1)
        .contentShape(Theme.card)
        .onHover { h in withAnimation(.easeOut(duration: 0.12)) { hovering = h } }
        .onTapGesture(count: 2) { store.editing = alarm }
        .contextMenu {
            Button("Test ring", systemImage: "play.fill") { store.testRing(alarm) }
            Button("Edit…", systemImage: "pencil") { store.editing = alarm }
            Button("Duplicate", systemImage: "plus.square.on.square") { store.duplicate(alarm.id) }
            Divider()
            Button("Delete", systemImage: "trash", role: .destructive) { store.delete(alarm.id) }
        }
        .accessibilityElement(children: .contain)
    }

    private func iconButton(_ symbol: String, _ help: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).frame(width: 26, height: 26)
        }
        .buttonStyle(.borderless)
        .help(help)
        .accessibilityLabel(help)
    }
}
