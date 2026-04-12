// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "DeskBeat",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "DeskBeat",
            path: "Sources/DeskBeat",
            exclude: ["Info.plist"],
            resources: [
                .copy("Resources/Sounds"),
                .copy("Resources/images")
            ],
            linkerSettings: [
                .linkedFramework("AVFoundation"),
                .linkedFramework("AppKit"),
                .linkedFramework("IOKit")
            ]
        )
    ]
)
