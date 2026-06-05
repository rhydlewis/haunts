// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "zforfinder",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "zforfinder",
            path: "Sources/zforfinder"
        )
    ]
)
