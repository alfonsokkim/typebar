// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Typebar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Typebar", targets: ["Typebar"])],
    targets: [
        .target(name: "TypingCore", resources: [.process("Resources")]),
        .executableTarget(name: "Typebar", dependencies: ["TypingCore"],
                          swiftSettings: [.defaultIsolation(MainActor.self),
                                          .enableUpcomingFeature("NonisolatedNonsendingByDefault")]),
        .testTarget(name: "TypingCoreTests", dependencies: ["TypingCore"]),
        .testTarget(name: "TypebarTests", dependencies: ["Typebar"])
    ]
)
