// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "MacBeat",
    platforms: [
        .macOS(.v14)
    ],
    targets: [
        .executableTarget(
            name: "MacBeat",
            path: "Sources/MacBeat",
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
