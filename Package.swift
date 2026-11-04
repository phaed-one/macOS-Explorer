// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Explorer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Explorer", targets: ["Explorer"])],
    targets: [
        .target(name: "PathfindCore"),
        .executableTarget(name: "Explorer", dependencies: ["PathfindCore"], path: "Sources/Pathfind"),
        .executableTarget(name: "PathfindChecks", dependencies: ["PathfindCore"], path: "Tests/PathfindCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
