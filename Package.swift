// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ConnorGraphAgentMac",
    defaultLocalization: "zh-Hans",
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
    dependencies: [
        .package(url: "https://github.com/vincedev/MailCoreSPM", branch: "master")
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
                "ConnorGraphAgent",
                .product(name: "MailCore", package: "MailCoreSPM")
            ],
            linkerSettings: [
                .linkedFramework("Security"),
                .linkedFramework("EventKit"),
                .linkedFramework("Contacts"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "ConnorGraphAgentMac",
            dependencies: ["ConnorGraphAgent", "ConnorGraphStore", "ConnorGraphAppSupport"],
            exclude: ["Info.plist"],
            resources: [
                .process("Assets.xcassets"),
                .process("zh-Hans.lproj"),
                .process("Resources/ThirdPartyNotices"),
                .copy("Resources/FoundationKG")
            ],
            linkerSettings: [
                .linkedFramework("WebKit"),
                .linkedFramework("AVFoundation"),
                .linkedFramework("Speech"),
                .linkedFramework("CoreLocation"),
                .linkedFramework("EventKit"),
                .linkedFramework("Contacts"),
                .unsafeFlags([
                    "-Xlinker", "-sectcreate",
                    "-Xlinker", "__TEXT",
                    "-Xlinker", "__info_plist",
                    "-Xlinker", "Sources/ConnorGraphAgentMac/Info.plist"
                ])
            ]
        ),
        .executableTarget(
            name: "ConnorCLI",
            dependencies: ["ConnorGraphAppSupport", "ConnorGraphCore"]
        ),
        .executableTarget(
            name: "ConnorFoundationKGSeedBuilder",
            dependencies: ["ConnorGraphAppSupport", "ConnorGraphStore", "ConnorGraphCore"]
        ),
        .testTarget(name: "ConnorGraphCoreTests", dependencies: ["ConnorGraphCore"]),
        .testTarget(name: "ConnorGraphMemoryTests", dependencies: ["ConnorGraphMemory"]),
        .testTarget(name: "ConnorGraphStoreTests", dependencies: ["ConnorGraphStore", "ConnorGraphCore"]),
        .testTarget(name: "ConnorGraphSearchTests", dependencies: ["ConnorGraphSearch"]),
        .testTarget(name: "ConnorGraphAgentTests", dependencies: ["ConnorGraphAgent"]),
        .testTarget(name: "ConnorGraphAgentMacTests", dependencies: ["ConnorGraphAgentMac"]),
        .testTarget(name: "ConnorGraphAppSupportTests", dependencies: ["ConnorGraphAppSupport"])
    ]
)
