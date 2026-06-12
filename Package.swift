// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConnorGraphAgentMac",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "ConnorGraphCore", targets: ["ConnorGraphCore"]),
        .library(name: "ConnorGraphMemory", targets: ["ConnorGraphMemory"]),
        .library(name: "ConnorGraphStore", targets: ["ConnorGraphStore"]),
        .library(name: "ConnorGraphSearch", targets: ["ConnorGraphSearch"]),
        .library(name: "ConnorGraphAgent", targets: ["ConnorGraphAgent"]),
        .library(name: "ConnorGraphAppSupport", targets: ["ConnorGraphAppSupport"]),
        .executable(name: "connor-graph-agent-mac", targets: ["ConnorGraphAgentMac"]),
        .executable(name: "connor", targets: ["ConnorCLI"])
    ],
    targets: [
        .target(name: "ConnorGraphCore"),
        .target(name: "ConnorGraphMemory", dependencies: ["ConnorGraphCore"]),
        .target(
            name: "ConnorGraphStore",
            dependencies: ["ConnorGraphCore", "ConnorGraphMemory", "ConnorGraphSearch"],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .target(name: "ConnorGraphSearch", dependencies: ["ConnorGraphCore", "ConnorGraphMemory"]),
        .target(name: "ConnorGraphAgent", dependencies: ["ConnorGraphCore", "ConnorGraphMemory", "ConnorGraphSearch"]),
        .target(
            name: "ConnorGraphAppSupport",
            dependencies: [
                "ConnorGraphCore",
                "ConnorGraphMemory",
                "ConnorGraphStore",
                "ConnorGraphSearch",
                "ConnorGraphAgent"
            ],
            linkerSettings: [.linkedFramework("Security")]
        ),
        .executableTarget(
            name: "ConnorGraphAgentMac",
            dependencies: ["ConnorGraphAgent", "ConnorGraphStore", "ConnorGraphAppSupport"],
            linkerSettings: [.linkedFramework("WebKit")]
        ),
        .executableTarget(
            name: "ConnorCLI",
            dependencies: ["ConnorGraphAppSupport", "ConnorGraphCore"]
        ),
        .testTarget(name: "ConnorGraphCoreTests", dependencies: ["ConnorGraphCore"]),
        .testTarget(name: "ConnorGraphMemoryTests", dependencies: ["ConnorGraphMemory"]),
        .testTarget(name: "ConnorGraphStoreTests", dependencies: ["ConnorGraphStore", "ConnorGraphCore"]),
        .testTarget(name: "ConnorGraphSearchTests", dependencies: ["ConnorGraphSearch"]),
        .testTarget(name: "ConnorGraphAgentTests", dependencies: ["ConnorGraphAgent"]),
        .testTarget(name: "ConnorGraphAppSupportTests", dependencies: ["ConnorGraphAppSupport"])
    ]
)
