// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "CineFlowPackage",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .tvOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "RemoteMediaLibrary", targets: ["RemoteMediaLibrary"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "SharedDemo", targets: ["SharedDemo"]),
        .library(name: "DandanApi", targets: ["DandanApi"]),
        .library(name: "DependenciesMacro", targets: ["DependenciesMacro"]),
    ],
    dependencies: [
        .package(path: "../Packages/SubtitleRenderer"),
        .package(path: "../Packages/DanmakuRenderer"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.1"),
        .package(url: "https://github.com/apple/swift-openapi-generator", from: "1.10.3"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.11.0"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.2.0"),
        .package(url: "https://github.com/mpvkit/MPVKit.git", exact: "0.41.0"),
        .package(url: "https://github.com/pointfreeco/swift-composable-architecture", from: "1.22.3"),
        .package(url: "https://github.com/swiftlang/swift-syntax", "509.0.0"..<"603.0.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Shared",
            dependencies: [
                "RemoteMediaLibrary",
                "DandanApi",
                "DependenciesMacro",
                .target(name: "SubtitleFFmpegBridge", condition: .when(platforms: [.iOS, .macOS, .tvOS])),
                .product(name: "SubtitleRendererCore", package: "SubtitleRenderer"),
                .product(name: "SubtitleRendererLibass", package: "SubtitleRenderer", condition: .when(platforms: [.macOS])),
                .product(name: "DanmakuRendererCore", package: "DanmakuRenderer"),
                .product(name: "DanmakuRendererCanvas", package: "DanmakuRenderer"),
                .product(name: "MPVKit", package: "MPVKit", condition: .when(platforms: [.iOS, .macOS, .tvOS])),
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture"),
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-testing"], .when(configuration: .debug))
            ],
            plugins: [
                .plugin(name: "BuildPlugin")
            ],
        ),
        .target(
            name: "SubtitleFFmpegBridge",
            dependencies: [
                .product(name: "MPVKit", package: "MPVKit", condition: .when(platforms: [.iOS, .macOS, .tvOS])),
            ],
            publicHeadersPath: "include"
        ),
        .target(
            name: "SharedDemo",
            dependencies: [
                "Shared"
            ]
        ),
        .testTarget(
            name: "SharedTests",
            dependencies: [
                "Shared"
            ]
        ),
        .target(
            name: "RemoteMediaLibrary",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .target(
            name: "DandanApi",
            dependencies: [
                .product(name: "OpenAPIRuntime", package: "swift-openapi-runtime"),
                .product(name: "OpenAPIURLSession", package: "swift-openapi-urlsession"),
            ],
            plugins: [
                .plugin(name: "OpenAPIGenerator", package: "swift-openapi-generator")
            ]
        ),
        .macro(
            name: "DependenciesMacroImpl",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(
            name: "DependenciesMacro",
            dependencies: [
                "DependenciesMacroImpl",
                .product(name: "ComposableArchitecture", package: "swift-composable-architecture")
            ]
        ),
        .executableTarget(
            name: "SecretGenerator",
            dependencies: [
                .product(name: "ArgumentParser", package:"swift-argument-parser")
            ]
        ),
        .plugin(
            name: "BuildPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "SecretGenerator")
            ]
        ),
    ],
)
