// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "RudeAwakening",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "RudeAwakening", targets: ["RudeAwakening"]),
        .executable(name: "rudectl", targets: ["rudectl"]),
        .library(name: "AlarmCore", targets: ["AlarmCore"]),
    ],
    targets: [
        // Everything that does not need a window: models, recurrence maths,
        // the OpenRouter client, the offline parser and the sound synthesiser.
        .target(name: "AlarmCore"),
        // The Mac app itself (SwiftUI + AppKit).
        .executableTarget(name: "RudeAwakening", dependencies: ["AlarmCore"]),
        // A small command-line tool for trying prompts, running evals and rendering sounds.
        .executableTarget(name: "rudectl", dependencies: ["AlarmCore"]),
        .testTarget(name: "AlarmCoreTests", dependencies: ["AlarmCore"]),
    ]
)
