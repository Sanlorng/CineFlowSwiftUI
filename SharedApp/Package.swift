// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CineFlowPackage",
    platforms: [
        .iOS(.v26),
        .macOS(.v26),
        .visionOS(.v26)
    ],
    products: [
        .library(name: "RemoteMediaLibrary", targets: ["RemoteMediaLibrary"]),
        .library(name: "Shared", targets: ["Shared"]),
        .library(name: "SharedDemo", targets: ["SharedDemo"]),
        .library(name: "DandanApi", targets: ["DandanApi"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.6.1"),
        .package(url: "https://github.com/apple/swift-openapi-generator.git", from: "1.10.3"),
        .package(url: "https://github.com/apple/swift-openapi-runtime", from: "1.8.3"),
        .package(url: "https://github.com/apple/swift-openapi-urlsession", from: "1.1.0"),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "Shared",
            dependencies: [
                "RemoteMediaLibrary",
                "DandanApi"
            ],
            swiftSettings: [
                .unsafeFlags(["-enable-testing"], .when(configuration: .debug))
            ],
            plugins: [
                .plugin(name: "BuildPlugin")
            ]
        ),
        .target(
            name: "SharedDemo",
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
