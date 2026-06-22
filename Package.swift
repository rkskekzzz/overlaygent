// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PersonaWritingAgent",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "PersonaWritingAgent",
            targets: ["PersonaWritingAgent"]
        )
    ],
    targets: [
        .executableTarget(
            name: "PersonaWritingAgent",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "PersonaWritingAgentTests",
            dependencies: ["PersonaWritingAgent"]
        )
    ]
)
