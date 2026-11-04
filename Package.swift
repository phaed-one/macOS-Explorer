// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Explorer",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Explorer", targets: ["Explorer"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1")],
    targets: [
        .target(name: "PathfindCore"),
        .executableTarget(name: "Explorer", dependencies: ["PathfindCore", .product(name: "Sparkle", package: "Sparkle")], path: "Sources/Pathfind",
            linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "PathfindChecks", dependencies: ["PathfindCore"], path: "Tests/PathfindCoreTests")
    ],
    swiftLanguageModes: [.v5]
)
