// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Sevi",
    platforms: [.macOS("14.2")],
    targets: [
        .target(name: "SeviCore"),
        .testTarget(name: "SeviCoreTests", dependencies: ["SeviCore"]),
    ]
)
