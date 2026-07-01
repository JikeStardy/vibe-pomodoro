// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "VibePomodoro",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "VibePomodoro",
            path: "Sources",
            exclude: ["App/Info.plist", "App/VibePomodoro.entitlements"],
            resources: [.process("Resources")]
        )
    ]
)
