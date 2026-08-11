// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RokidLyrics",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(name: "RokidLyricsCore", targets: ["RokidLyricsCore"]),
        .library(name: "RokidLyricsServices", targets: ["RokidLyricsServices"]),
    ],
    targets: [
        .target(name: "RokidLyricsCore"),
        .target(
            name: "RokidLyricsServices",
            dependencies: ["RokidLyricsCore"]
        ),
        .testTarget(
            name: "RokidLyricsCoreTests",
            dependencies: ["RokidLyricsCore"]
        ),
        .testTarget(
            name: "RokidLyricsServicesTests",
            dependencies: ["RokidLyricsCore", "RokidLyricsServices"]
        ),
    ]
)

