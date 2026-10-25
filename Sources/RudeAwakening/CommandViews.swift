import AlarmCore
import SwiftUI

/// The sentence box. Used in the main window, the menu bar panel and the quick-entry panel.
struct CommandField: View {
    enum Style { case large, compact, spotlight }

    var style: Style = .large
    @Binding var text: String
    var onSubmitted: (Bool) -> Void = { _ in }

    @EnvironmentObject private var store: AlarmStore
    @FocusState private var focused: Bool
    @State private var placeholder = Cheek.placeholders[0]
    @State private var thinkingLine = Cheek.thinking[0]

    private var fontSize: CGFloat {
        switch style {
        case .large: return 18
        case .compact: return 14
        case .spotlight: return 24
        }
    }

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "sparkles")
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundStyle(Theme.brand)
                .symbolEffect(.pulse, isActive: store.isThinking)
            TextField(store.isThinking ? thinkingLine : placeholder, text: $text, axis: .vertical)
                .textFieldStyle(.plain)
                .font(Theme.display(fontSize, .semibold))
                .lineLimit(1...3)
                .focused($focused)
                .disabled(store.isThinking)
                .onSubmit(send)
                .accessibilityLabel("Tell Rude Awakening when to ring")
            if store.isThinking {
                ProgressView().controlSize(.small)
            } else {
                Button(action: send) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: fontSize + 8))
                        .foregroundStyle(text.trimmed.isEmpty ? AnyShapeStyle(.tertiary) : AnyShapeStyle(Theme.hero))
                }
                .buttonStyle(.plain)
                .disabled(text.trimmed.isEmpty)
                .keyboardShortcut(.defaultAction)
                .help("Set it (Return)")
                .accessibilityLabel("Set alarm")
            }
        }
        .padding(.horizontal, style == .compact ? 12 : 16)
        .padding(.vertical, style == .compact ? 9 : 14)
        .background {
            if style != .spotlight {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .textBackgroundColor))
                    .shadow(color: .black.opacity(0.06), radius: 6, y: 2)
            }
        }
        .overlay {
            if style != .spotlight {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(focused ? AnyShapeStyle(Theme.brand) : AnyShapeStyle(Color.primary.opacity(0.1)), lineWidth: focused ? 2 : 1)
            }
        }
        .onAppear { focused = style != .compact }
        .onReceive(NotificationCenter.default.publisher(for: .quickEntryOpened)) { _ in
            if style == .spotlight { focused = true }
        }
        .task {
            var i = 0
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(store.isThinking ? 1.2 : 3.5))
                i += 1
                placeholder = Cheek.placeholders[i % Cheek.placeholders.count]
                thinkingLine = Cheek.thinking[i % Cheek.thinking.count]
            }
        }
    }

    private func send() {
        let sentence = text.trimmed
        guard !sentence.isEmpty else { return }
        Task {
            let changed = await store.submit(sentence)
            if changed { text = "" }
            onSubmitted(changed)
            focused = true
        }
    }
}

/// Tap-to-fill example sentences above the box.
struct ExampleChips: View {
    @Binding var text: String

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(Cheek.examples, id: \.self) { example in
                    Button { text = example } label: {
                        Text(example)
                            .font(.callout)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 5)
                            .background(.quaternary.opacity(0.6), in: Capsule())
                    }
                    .buttonStyle(.plain)
                    .help("Use this example")
                }
            }
        }
    }
}

/// What the brain understood: its cheeky reply, then a card per alarm with the exact time.
struct OutcomeCard: View {
    let outcome: CommandOutcome
    var compact = false

    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var ticker: Ticker

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if !outcome.reply.isEmpty {
                HStack(alignment: .top, spacing: 10) {
                    Text("⏰").font(.title2).accessibilityHidden(true)
                    Text(outcome.reply)
                        .font(Theme.display(compact ? 13 : 15, .medium))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 8)
                        .background(Theme.hot.opacity(0.1), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            ForEach(outcome.created) { alarm in
                CreatedAlarmRow(alarm: alarm, undone: outcome.undone)
            }
            ForEach(outcome.deleted) { alarm in
                Label("Deleted “\(alarm.displayLabel)”", systemImage: "trash")
                    .font(.callout).foregroundStyle(.secondary)
                    .strikethrough(!outcome.undone)
            }
            ForEach(outcome.toggled, id: \.id) { change in
                if let a = store.alarms.first(where: { $0.id == change.id }) {
                    Label("\(a.isEnabled ? "Turned on" : "Turned off") “\(a.displayLabel)”", systemImage: a.isEnabled ? "bell" : "bell.slash")
                        .font(.callout).foregroundStyle(.secondary)
                }
            }
            ForEach(outcome.notes, id: \.self) { note in
                Label(note, systemImage: "info.circle").font(.callout).foregroundStyle(.orange)
                    .fixedSize(horizontal: false, vertical: true)
            }
            ForEach(outcome.problems, id: \.self) { problem in
                Label(problem, systemImage: "exclamationmark.triangle.fill").font(.callout).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if outcome.changedSomething && !compact {
                HStack {
                    if outcome.undone {
                        Text("Undone. Like it never happened.").font(.caption).foregroundStyle(.secondary)
                    } else {
                        Button("Undo", systemImage: "arrow.uturn.backward") { store.undo() }
                            .buttonStyle(.borderless)
                            .keyboardShortcut("z", modifiers: .command)
                    }
                    Spacer()
                    Button("Dismiss", systemImage: "xmark") { store.outcome = nil }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Dismiss")
                }
                .font(.callout)
            }
        }
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

/// Saturn-style card: "⟳ Weekdays at 7:15 AM · Gym", with when it will next ring.
struct CreatedAlarmRow: View {
    let alarm: Alarm
    var undone = false

    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var ticker: Ticker

    var body: some View {
        // The outcome keeps a copy from when it was made; show the alarm as it is now (snoozed, moved, deleted).
        let live = store.alarms.first { $0.id == alarm.id }
        let shown = live ?? alarm
        HStack(spacing: 12) {
            Image(systemName: shown.isOneOff ? "alarm.fill" : "repeat")
                .font(.system(size: 16, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 34, height: 34)
                .background(Theme.hero, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(shown.displayLabel).font(.headline)
                Text(Describe.schedule(shown, now: ticker.now, calendar: store.calendar))
                    .font(.callout).foregroundStyle(.secondary)
            }
            Spacer()
            if live != nil, let next = store.nextFire(shown), !undone {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("in \(Describe.countdown(from: ticker.now, to: next))")
                        .font(Theme.display(14, .bold)).monospacedDigit()
                        .foregroundStyle(Theme.hot)
                    if !shown.isOneOff {
                        Text("next: \(Describe.when(next, now: ticker.now, calendar: store.calendar))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        .padding(10)
        .background(.background.secondary, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
        .opacity(undone ? 0.45 : 1)
        .accessibilityElement(children: .combine)
    }
}
