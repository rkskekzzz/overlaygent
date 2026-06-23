// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Overlaygent",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(
            name: "Overlaygent",
            targets: ["Overlaygent"]
        )
    ],
    targets: [
        .executableTarget(
            name: "Overlaygent",
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "OverlaygentTests",
            dependencies: ["Overlaygent"]
        )
    ]
)
