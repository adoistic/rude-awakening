import AlarmCore
import SwiftUI

/// The menu bar item: an alarm clock, plus a countdown when something rings within a day.
struct MenuBarLabel: View {
    @ObservedObject private var store = AlarmStore.shared
    @ObservedObject private var ticker = Ticker.shared
    @ObservedObject private var prefs = Prefs.shared

    var body: some View {
        if store.ringing != nil {
            Image(systemName: "alarm.waves.left.and.right.fill")
        } else if prefs.showCountdown, let next = store.nextUp, next.date.timeIntervalSince(ticker.now) < 86_400 {
            HStack(spacing: 3) {
                Image(systemName: "alarm.fill")
                Text(Describe.countdown(from: ticker.now, to: next.date)).monospacedDigit()
            }
        } else {
            Image(systemName: store.hasArmedAlarms ? "alarm.fill" : "alarm")
        }
    }
}

struct MenuBarPanel: View {
    @ObservedObject private var store = AlarmStore.shared
    @ObservedObject private var ticker = Ticker.shared
    @State private var text = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                AppMark(size: 28)
                Text("Rude Awakening").font(Theme.display(16, .heavy))
                Spacer()
                Button { WindowManager.shared.showSettings() } label: { Image(systemName: "gearshape.fill") }
                    .buttonStyle(.borderless)
                    .help("Settings")
                    .accessibilityLabel("Settings")
            }

            if let session = store.ringing {
                Button {
                    RingWindowManager.shared.show()
                } label: {
                    Label("Ringing: \(session.labels.first ?? "wake up")", systemImage: "alarm.waves.left.and.right.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .tint(Theme.hot)
            }

            CommandField(style: .compact, text: $text)

            if let outcome = store.outcome {
                OutcomeCard(outcome: outcome, compact: true)
            }

            Divider()

            if store.upcoming.isEmpty {
                Text(Cheek.empty[1]).foregroundStyle(.secondary).font(.callout)
            } else {
                Text("NEXT UP").font(.caption.weight(.heavy)).tracking(1.2).foregroundStyle(.secondary)
                ForEach(store.upcoming.prefix(5)) { alarm in
                    if let next = store.nextFire(alarm) {
                        HStack {
                            BigClock(date: next, size: 17, weight: .bold)
                            Text(alarm.displayLabel).lineLimit(1)
                            Spacer()
                            Text("in \(Describe.countdown(from: ticker.now, to: next))")
                                .monospacedDigit().foregroundStyle(Theme.hot).font(.callout.weight(.semibold))
                        }
                    }
                }
            }

            Divider()

            HStack {
                Button("Open Rude Awakening") { WindowManager.shared.showMain() }
                Spacer()
                Button("Quit") { WindowManager.shared.quitApp() }
            }
            .buttonStyle(.borderless)
        }
        .padding(14)
        .frame(width: 360)
        .environmentObjects()
    }
}

/// The ⌥⌘A box: type a sentence from any app, press Return, get on with your life.
struct QuickEntryView: View {
    let close: () -> Void
    @EnvironmentObject private var store: AlarmStore
    @State private var text = ""
    @State private var justSet = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            CommandField(style: .spotlight, text: $text) { changed in
                guard changed else { return }
                justSet = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 2.4) {
                    if justSet { close(); justSet = false }
                }
            }
            if let outcome = store.outcome, justSet || !outcome.problems.isEmpty {
                OutcomeCard(outcome: outcome, compact: true)
            }
        }
        .padding(18)
        .frame(width: 640)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 22, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 22, style: .continuous).strokeBorder(Theme.brand, lineWidth: 2))
        .onExitCommand(perform: close)
        .onChange(of: text) { _, _ in justSet = false }
    }
}
