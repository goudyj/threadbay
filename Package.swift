// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orchestrate",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", from: "5.1.0"),
        .package(url: "https://github.com/migueldeicaza/SwiftTerm.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "OrchestrateCore",
            dependencies: ["Yams"]
        ),
        .executableTarget(
            name: "Orchestrate",
            dependencies: ["OrchestrateCore", "SwiftTerm"]
        ),
        .testTarget(
            name: "OrchestrateCoreTests",
            dependencies: ["OrchestrateCore"]
        ),
    ]
)
