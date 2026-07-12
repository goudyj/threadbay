// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orchestrate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
    ],
    targets: [
        .target(
            name: "OrchestrateCore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "Orchestrate",
            dependencies: ["OrchestrateCore"]
        ),
        .testTarget(
            name: "OrchestrateCoreTests",
            dependencies: ["OrchestrateCore"]
        ),
    ]
)
