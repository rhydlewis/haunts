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
        // Editor signal sources (Zed/Xcode/PyCharm recent folders). Foundation-only,
        // never-throw. Standalone so it's testable without the executable. Not yet
        // wired into the app shell — that happens in a later session.
        .target(
            name: "HauntsAdapters",
            path: "Sources/HauntsAdapters"
        ),
        // App shell: @MainActor state + impure adapters (git scan, Spotlight, open).
        .executableTarget(
            name: "zforfinder",
            dependencies: ["ZFFEngine"],
            path: "Sources/zforfinder"
        ),
        .testTarget(
            name: "ZFFEngineTests",
            dependencies: ["ZFFEngine", "HauntsAdapters"],
            path: "Tests/ZFFEngineTests"
        )
    ]
)
