// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BarClaw",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "BarClaw",
            path: "Sources/BarClaw"
        )
    ]
)
