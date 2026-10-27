// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "ActivityCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "ActivityCore", targets: ["ActivityCore"])],
    targets: [
        .target(name: "ActivityCore", path: "Shared"),
        .testTarget(name: "ActivityCoreTests", dependencies: ["ActivityCore"], path: "Tests/ActivityCoreTests")
    ]
)
