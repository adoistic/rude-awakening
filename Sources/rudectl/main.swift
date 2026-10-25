import AlarmCore
import Foundation

// rudectl: try the brain and the sounds without the app.
//
//   rudectl parse "every weekday at 7:15 for gym"   ask OpenRouter and show what would be set
//   rudectl local "tomorrow at 7"                    the offline parser only
//   rudectl eval [model]                             run the prompt eval suite at a fixed "now"
//   rudectl sounds <folder>                          write every alarm sound as a WAV
//
// The key comes from OPENROUTER_API_KEY, or the app's saved key.

let args = Array(CommandLine.arguments.dropFirst())

func apiKey() -> String? {
    if let k = ProcessInfo.processInfo.environment["OPENROUTER_API_KEY"], !k.isEmpty { return k }
    let url = FileManager.default.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Application Support/Rude Awakening/openrouter-key")
    return (try? String(contentsOf: url, encoding: .utf8))?.trimmingCharacters(in: .whitespacesAndNewlines)
}

func model() -> String {
    ProcessInfo.processInfo.environment["RUDE_MODEL"] ?? OpenRouterClient.defaultModel
}

func show(_ resolved: ResolvedPlan, now: Date, calendar: Calendar) {
    for a in resolved.alarms {
        let next = a.nextFire(calendar: calendar).map { Describe.when($0, now: now, calendar: calendar) } ?? "never"
        print("  + \(Describe.schedule(a, now: now, calendar: calendar)) | label: \(a.label.isEmpty ? "-" : a.label) | sound: \(a.soundID ?? "default") | next: \(next)")
    }
    for id in resolved.deleteIDs { print("  - delete \(id.uuidString.prefix(8))") }
    for id in resolved.disableIDs { print("  ~ off \(id.uuidString.prefix(8))") }
    for id in resolved.enableIDs { print("  ~ on \(id.uuidString.prefix(8))") }
    for n in resolved.notes { print("  note: \(n)") }
    for p in resolved.problems { print("  problem: \(p)") }
    if !resolved.reply.isEmpty { print("  reply: \(resolved.reply)") }
}

func run() async -> Int32 {
    guard let command = args.first else {
        print("usage: rudectl parse|local|eval|sounds …")
        return 1
    }
    let calendar = Calendar.autoupdatingCurrent
    let now = Date()

    switch command {
    case "parse":
        let text = args.dropFirst().joined(separator: " ")
        guard let key = apiKey() else { print("No key: set OPENROUTER_API_KEY"); return 1 }
        let client = OpenRouterClient(apiKey: key, model: model())
        let started = Date()
        do {
            let plan = try await client.plan(for: text, systemPrompt: Prompt.system(now: now, calendar: calendar, existing: []))
            print("model \(client.model) took \(String(format: "%.1f", Date().timeIntervalSince(started)))s")
            show(PlanResolver.resolve(plan, prompt: text, existing: [], now: now, calendar: calendar), now: now, calendar: calendar)
        } catch {
            print("error: \(error.localizedDescription)")
            return 1
        }

    case "local":
        let text = args.dropFirst().joined(separator: " ")
        show(LocalParser.parse(text, now: now, calendar: calendar), now: now, calendar: calendar)

    case "eval":
        guard let key = apiKey() else { print("No key: set OPENROUTER_API_KEY"); return 1 }
        let m = args.count > 1 ? args[1] : model()
        return await Evals.run(client: OpenRouterClient(apiKey: key, model: m))

    case "sounds":
        let folder = URL(fileURLWithPath: args.count > 1 ? args[1] : "sounds")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for s in SoundLibrary.all {
            let started = Date()
            let samples = SoundSynth.render(s.id)
            let st = SoundSynth.stats(samples)
            try? SoundSynth.wav(samples).write(to: folder.appendingPathComponent("\(s.id).wav"))
            print(String(format: "%-10@ %5.1fs  peak %.2f  rms %6.1f dBFS  rendered in %.0f ms",
                         s.id as NSString, st.seconds, st.peak, st.rmsDB, Date().timeIntervalSince(started) * 1000))
        }

    default:
        print("unknown command \(command)")
        return 1
    }
    return 0
}

exit(await run())
