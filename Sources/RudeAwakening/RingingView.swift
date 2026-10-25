import AlarmCore
import AppKit
import SwiftUI

/// The full-screen alarm. What the alarm is FOR is the headline, because at 6 AM
/// "7:15" means nothing and "FLIGHT TO DUBAI" means everything.
struct RingingView: View {
    let isPrimary: Bool

    @EnvironmentObject private var store: AlarmStore
    @EnvironmentObject private var prefs: Prefs
    @State private var started = Date()
    @State private var holdProgress: CGFloat = 0
    @State private var challenge = MathChallenge.make(.easy)
    @State private var answer = ""
    @State private var wrong: String?
    @State private var shake: CGFloat = 0
    @FocusState private var answerFocused: Bool

    private var reduceMotion: Bool { NSWorkspace.shared.accessibilityDisplayShouldReduceMotion }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSince(started)
            ZStack {
                background(t)
                if let session = store.ringing {
                    content(session, now: context.date, t: t)
                        .padding(48)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear {
            started = Date()
            challenge = MathChallenge.make(prefs.challenge == .hard ? .hard : .easy)
            answerFocused = isPrimary
        }
    }

    // MARK: Layout

    @ViewBuilder
    private func content(_ session: RingSession, now: Date, t: Double) -> some View {
        let emoji = SoundLibrary.info(for: session.soundID)?.emoji ?? "⏰"
        VStack(spacing: 22) {
            HStack(spacing: 14) {
                Text(emoji)
                    .font(.system(size: 64))
                    .rotationEffect(.degrees(reduceMotion ? 0 : sin(t * 14) * 14))
                    .accessibilityHidden(true)
                BigClock(date: now, size: 64, weight: .heavy).foregroundStyle(.white.opacity(0.92))
                if session.isTest { Chip(text: "TEST RING", tint: .white) }
            }

            reasons(session)

            Text(Cheek.taunts[Int(t / 3.5) % Cheek.taunts.count])
                .font(Theme.display(26, .semibold))
                .foregroundStyle(.white.opacity(0.9))
                .contentTransition(.opacity)
                .animation(.easeInOut, value: Int(t / 3.5))

            if session.volumeFights > 0 {
                Text("You tried to turn me down \(session.volumeFights)×. \(Cheek.volumeFights[(session.volumeFights - 1) % Cheek.volumeFights.count])")
                    .font(.headline)
                    .padding(.horizontal, 14).padding(.vertical, 7)
                    .background(.black.opacity(0.25), in: Capsule())
                    .foregroundStyle(.white)
            }

            Spacer().frame(height: 6)

            if isPrimary {
                controls(session)
            } else {
                Text("Make it stop on your main screen.")
                    .font(.title3.weight(.semibold)).foregroundStyle(.white.opacity(0.85))
            }

            footer(session, now: now)
        }
        .frame(maxWidth: 1000)
    }

    /// Every alarm that is ringing, and why.
    @ViewBuilder
    private func reasons(_ session: RingSession) -> some View {
        VStack(spacing: 14) {
            ForEach(session.reasons) { reason in
                VStack(spacing: 8) {
                    if reason.label.isEmpty {
                        Text("WAKE UP")
                            .font(Theme.display(session.reasons.count > 1 ? 64 : 110, .black))
                            .minimumScaleFactor(0.4)
                        Text(Cheek.noReason[Int(reason.id.uuid.0) % Cheek.noReason.count])
                            .font(Theme.display(22, .medium))
                            .opacity(0.85)
                    } else {
                        Text(reason.label.uppercased())
                            .font(Theme.display(session.reasons.count > 1 ? 64 : 110, .black))
                            .multilineTextAlignment(.center)
                            .lineLimit(2)
                            .minimumScaleFactor(0.35)
                    }
                    if let prompt = reason.prompt, !prompt.isEmpty, prompt.lowercased() != reason.label.lowercased() {
                        Text("You said: “\(prompt)”")
                            .font(Theme.display(20, .medium))
                            .multilineTextAlignment(.center)
                            .lineLimit(3)
                            .opacity(0.8)
                    } else {
                        Text(reason.schedule).font(Theme.display(20, .medium)).opacity(0.8)
                    }
                }
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
                .accessibilityElement(children: .combine)
                .accessibilityLabel("Alarm: \(reason.label.isEmpty ? "wake up" : reason.label)")
            }
        }
    }

    @ViewBuilder
    private func controls(_ session: RingSession) -> some View {
        let needsMaths = prefs.challenge != .off && !session.isTest
        VStack(spacing: 18) {
            if needsMaths {
                VStack(spacing: 10) {
                    Text("Prove you're awake: \(challenge.question) = ?")
                        .font(Theme.display(30, .heavy)).foregroundStyle(.white)
                    TextField("answer", text: $answer)
                        .textFieldStyle(.plain)
                        .font(Theme.display(34, .bold))
                        .multilineTextAlignment(.center)
                        .frame(width: 200)
                        .padding(.vertical, 10)
                        .background(.white, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                        .foregroundStyle(.black)
                        .focused($answerFocused)
                        .onSubmit(checkAnswer)
                        .offset(x: shake)
                    if let wrong { Text(wrong).font(.headline).foregroundStyle(.white) }
                }
            }

            HStack(spacing: 28) {
                Button { store.snooze(minutes: prefs.snoozeMinutes) } label: {
                    Text("Snooze \(prefs.snoozeMinutes) min (coward)")
                        .font(Theme.display(22, .bold))
                        .padding(.horizontal, 30).padding(.vertical, 18)
                        .background(Theme.sun, in: Capsule())
                        .foregroundStyle(.black)
                }
                .buttonStyle(.plain)
                .keyboardShortcut("s", modifiers: [])
                .help("Snooze (S)")

                if !needsMaths {
                    holdToStop
                }
            }
        }
    }

    /// Pillow-style: press and hold to stop, so a sleepy flail doesn't count.
    private var holdToStop: some View {
        VStack(spacing: 8) {
            ZStack {
                Circle().fill(.white)
                Circle()
                    .trim(from: 0, to: holdProgress)
                    .stroke(Theme.hot, style: StrokeStyle(lineWidth: 8, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                    .padding(5)
                Image(systemName: "stop.fill").font(.system(size: 34, weight: .black)).foregroundStyle(Theme.hot)
            }
            .frame(width: 104, height: 104)
            .shadow(color: .black.opacity(0.25), radius: 10, y: 4)
            .onLongPressGesture(minimumDuration: 1.2, maximumDistance: 60) {
                store.stopRinging()
            } onPressingChanged: { pressing in
                withAnimation(pressing ? .linear(duration: 1.2) : .easeOut(duration: 0.2)) {
                    holdProgress = pressing ? 1 : 0
                }
            }
            .accessibilityElement()
            .accessibilityLabel("Stop alarm")
            .accessibilityHint("Press and hold")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { store.stopRinging() }

            Text("Hold to stop · ⌘↩︎").font(.headline).foregroundStyle(.white)
            // Keyboard route for people who can't press and hold.
            Button("Stop") { store.stopRinging() }
                .keyboardShortcut(.return, modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
                .accessibilityHidden(true)
        }
    }

    private func footer(_ session: RingSession, now: Date) -> some View {
        let elapsed = Int(now.timeIntervalSince(session.startedAt))
        var parts = ["Ringing for \(elapsed / 60):\(String(format: "%02d", elapsed % 60))"]
        if session.isTest {
            parts.append("test rings stay at your current volume; real alarms crank it to \(Int(prefs.crankLevel * 100))%")
        } else if prefs.autoStopMinutes > 0 {
            parts.append("I give up in \(max(0, prefs.autoStopMinutes - elapsed / 60)) min")
        }
        return Text(parts.joined(separator: " · "))
            .font(.callout).monospacedDigit()
            .foregroundStyle(.white.opacity(0.75))
    }

    // MARK: Background

    private func background(_ t: Double) -> some View {
        let phase = reduceMotion ? 0 : (sin(t * 2.2) + 1) / 2
        let colors = [Theme.hot, Theme.ember, Color(red: 0.55, green: 0.08, blue: 0.35)]
        return ZStack {
            LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
            RadialGradient(colors: [Theme.sun.opacity(0.55 * phase), .clear], center: .center, startRadius: 40, endRadius: 700)
            Text("!!!")
                .font(.system(size: 520, weight: .black, design: .rounded))
                .foregroundStyle(.white.opacity(0.06))
                .rotationEffect(.degrees(reduceMotion ? -10 : -10 + sin(t * 3) * 3))
                .accessibilityHidden(true)
        }
    }

    // MARK: Maths

    private func checkAnswer() {
        if Int(answer.trimmed) == challenge.answer {
            store.stopRinging()
        } else {
            wrong = Cheek.pick(Cheek.wrongAnswer)
            answer = ""
            withAnimation(.spring(response: 0.15, dampingFraction: 0.2)) { shake = 14 }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.15) { withAnimation { shake = 0 } }
        }
    }
}

struct MathChallenge {
    let question: String
    let answer: Int

    enum Level { case easy, hard }

    static func make(_ level: Level) -> MathChallenge {
        switch level {
        case .easy:
            let a = Int.random(in: 12...59), b = Int.random(in: 12...49)
            return MathChallenge(question: "\(a) + \(b)", answer: a + b)
        case .hard:
            let a = Int.random(in: 6...19), b = Int.random(in: 3...9), c = Int.random(in: 11...49)
            return MathChallenge(question: "\(a) × \(b) + \(c)", answer: a * b + c)
        }
    }
}
