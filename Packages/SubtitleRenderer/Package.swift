// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "SubtitleRenderer",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "SubtitleRendererCore",
            targets: ["SubtitleRendererCore"]
        ),
        .library(
            name: "SubtitleRendererLibass",
            targets: ["SubtitleRendererLibass"]
        ),
    ],
    targets: [
        .target(
            name: "SubtitleRendererCore"
        ),
        .systemLibrary(
            name: "CLibass",
            path: "Sources/CLibass"
        ),
        .target(
            name: "SubtitleRendererLibass",
            dependencies: [
                "SubtitleRendererCore",
                "CLibass",
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "SubtitleRendererCoreTests",
            dependencies: [
                "SubtitleRendererCore",
                "SubtitleRendererLibass"
            ]
        ),
    ]
)
