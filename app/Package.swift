// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "zforfinder",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure ranking/scoring engine — no AppKit/SwiftUI/metadata. Unit-tested.
        .target(
            name: "ZFFEngine",
            path: "Sources/ZFFEngine"
        ),
        // App shell: @MainActor state + impure adapters (git scan, Spotlight, open).
        .executableTarget(
            name: "zforfinder",
            dependencies: ["ZFFEngine"],
            path: "Sources/zforfinder"
        ),
        .testTarget(
            name: "ZFFEngineTests",
            dependencies: ["ZFFEngine"],
            path: "Tests/ZFFEngineTests"
        )
    ]
)
