import Foundation

public struct SoundInfo: Identifiable, Hashable, Sendable {
    public let id: String
    public let name: String
    public let emoji: String
    public let blurb: String
    /// Words the language model can match ("goose", "brutal", "robot").
    public let vibe: String
}

/// The built-in alarm sounds. None of them are recordings: `SoundSynth` builds each
/// one from oscillators and filters at launch, so the app ships no audio files.
public enum SoundLibrary {
    public static let defaultID = "airhorn"

    public static let all: [SoundInfo] = [
        SoundInfo(id: "airhorn", name: "Air Horn Ambush", emoji: "📯",
                  blurb: "Stadium-grade honking. The neighbours will know.",
                  vibe: "air horn, brutal, loudest, stadium, party"),
        SoundInfo(id: "goose", name: "Angry Goose", emoji: "🪿",
                  blurb: "A goose with a grudge and no inside voice.",
                  vibe: "goose, honk, bird, animal, angry"),
        SoundInfo(id: "klaxon", name: "Submarine Panic", emoji: "🚨",
                  blurb: "AH-OOO-GAH. Dive, dive, get up.",
                  vibe: "klaxon, submarine, emergency, aoogah, old car horn"),
        SoundInfo(id: "microwave", name: "Microwave Rage", emoji: "📟",
                  blurb: "Your leftovers are ready. Forever.",
                  vibe: "beep, classic alarm clock, digital, microwave, piercing"),
        SoundInfo(id: "siren", name: "Disco Siren", emoji: "🪩",
                  blurb: "A police chase, but make it a dance floor.",
                  vibe: "siren, police, wail, disco, dance"),
        SoundInfo(id: "rooster", name: "Rooster on Espresso", emoji: "🐓",
                  blurb: "Cock-a-doodle-DO IT NOW.",
                  vibe: "rooster, morning, farm, crow, bird"),
        SoundInfo(id: "robot", name: "Robot Meltdown", emoji: "🤖",
                  blurb: "Beep boop. Error: human still horizontal.",
                  vibe: "robot, glitch, computer, sci-fi, bleeps"),
        SoundInfo(id: "kazoo", name: "Kazoo Riot", emoji: "🎺",
                  blurb: "A marching band of one very committed kazoo.",
                  vibe: "kazoo, fanfare, music, silly, trumpet, band"),
        SoundInfo(id: "dialup", name: "Dial-Up Nightmare", emoji: "📠",
                  blurb: "Connecting to 1998… please wake up.",
                  vibe: "dial-up, modem, retro, internet, screech, nostalgia"),
        SoundInfo(id: "chiptune", name: "8-Bit Tantrum", emoji: "👾",
                  blurb: "Game over, sleepyhead. Insert coin.",
                  vibe: "8-bit, chiptune, video game, arcade, retro music"),
        SoundInfo(id: "chaos", name: "Total Chaos", emoji: "🌪️",
                  blurb: "All of the above, back to back. You earned this.",
                  vibe: "random, surprise, chaos, everything, mix"),
    ]

    public static let ids: [String] = all.map(\.id)

    public static func info(for id: String) -> SoundInfo? {
        all.first { $0.id == id }
    }
}
