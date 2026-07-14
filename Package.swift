// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ThreadBay",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "ThreadBayCore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "ThreadBay",
            dependencies: ["ThreadBayCore", "SwiftTerm"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ThreadBayCoreTests",
            dependencies: ["ThreadBayCore"]
        ),
        .testTarget(
            name: "ThreadBayTests",
            dependencies: ["ThreadBay"]
        ),
    ]
)
