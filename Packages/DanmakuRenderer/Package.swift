// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "DanmakuRenderer",
    platforms: [
        .macOS(.v14),
        .iOS(.v16),
        .tvOS(.v16),
        .visionOS(.v1)
    ],
    products: [
        .library(
            name: "DanmakuRendererCore",
            targets: ["DanmakuRendererCore"]
        ),
        .library(
            name: "DanmakuRendererCanvas",
            targets: ["DanmakuRendererCanvas"]
        ),
    ],
    targets: [
        .target(
            name: "DanmakuRendererCore"
        ),
        .target(
            name: "DanmakuRendererCanvas",
            dependencies: [
                "DanmakuRendererCore"
            ]
        ),
        .testTarget(
            name: "DanmakuRendererCoreTests",
            dependencies: [
                "DanmakuRendererCore"
            ]
        ),
    ]
)
