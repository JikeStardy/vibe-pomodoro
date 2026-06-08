// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "NotchPomodoro",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "NotchPomodoro",
            path: "Sources",
            exclude: ["App/Info.plist", "App/NotchPomodoro.entitlements"]
        )
    ]
)
