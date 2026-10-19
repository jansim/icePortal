// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "IcePortalBar",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(
            name: "IcePortalBar",
            path: "Sources/IcePortalBar"
        )
    ]
)
