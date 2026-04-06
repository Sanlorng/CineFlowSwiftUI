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
            pkgConfig: "libass",
            providers: [
                .brew(["libass", "pkgconf"])
            ]
        ),
        .target(
            name: "SubtitleRendererLibass",
            dependencies: [
                "SubtitleRendererCore",
                "CLibass",
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
