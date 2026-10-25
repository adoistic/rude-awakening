import AlarmCore
import SwiftUI

/// First run: one screen, one key, done.
struct OnboardingView: View {
    let done: () -> Void
    @EnvironmentObject private var prefs: Prefs
    @State private var saved = false

    var body: some View {
        VStack(spacing: 0) {
            ZStack {
                Theme.brand
                Text("!!!")
                    .font(.system(size: 150, weight: .black, design: .rounded))
                    .foregroundStyle(.white.opacity(0.1))
                    .rotationEffect(.degrees(-8))
                    .accessibilityHidden(true)
                AppMark(size: 72)
            }
            .frame(height: 130)
            .clipped()

            VStack(alignment: .leading, spacing: 16) {
                Text("Hi. I'm Rude Awakening.").font(Theme.display(26, .black))
                Text("I'm a loud, slightly rude alarm clock. Tell me when to yell at you in plain English, like “every weekday at 7:15 for gym”. To understand you I need an OpenRouter key. One alarm costs a tiny fraction of a cent.")
                    .fixedSize(horizontal: false, vertical: true)

                KeyEntry {
                    saved = true
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) { done() }
                }

                VStack(alignment: .leading, spacing: 6) {
                    Label("Where do I get one?", systemImage: "questionmark.circle.fill").font(.headline)
                    Text("1. Sign in at openrouter.ai (Google or GitHub works).")
                    Text("2. Open Keys and press Create key.")
                    Text("3. Paste it above. That's the whole setup.")
                    Link("Open openrouter.ai/keys", destination: OpenRouterClient.keysPage).padding(.top, 2)
                }
                .font(.callout)
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 14, style: .continuous))

                Text("The key stays on this Mac and is only ever sent to openrouter.ai.")
                    .font(.caption).foregroundStyle(.secondary)
            }
            .padding(26)

            HStack {
                Button("Skip: I'll set alarms by hand") {
                    prefs.skippedOnboarding = true
                    done()
                }
                .buttonStyle(.link)
                Spacer()
                if saved { Label("All set", systemImage: "checkmark.circle.fill").foregroundStyle(.green) }
            }
            .padding([.horizontal, .bottom], 26)
        }
        .frame(width: 500)
    }
}
