// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "RightHere",
    defaultLocalization: "en",
    platforms: [
        .macOS(.v26)
    ],
    products: [
        // Pure logic: context, path styles, quoting, launch plans, config, menu model.
        .library(name: "RightHereCore", targets: ["RightHereCore"]),
        // macOS runtime: executes launch plans and answers questions about the live system.
        .library(name: "RightHereKit", targets: ["RightHereKit"]),
        .executable(name: "rh", targets: ["rh"])
    ],
    dependencies: [
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.5"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.5.0")
    ],
    targets: [
        .target(
            name: "RightHereCore",
            dependencies: [.product(name: "TOMLDecoder", package: "TOMLDecoder")]
        ),
        .target(
            name: "RightHereKit",
            dependencies: ["RightHereCore"]
        ),
        // A small MCP server over the action registry, written against the protocol directly.
        .target(
            name: "RightHereMCP",
            dependencies: ["RightHereCore", "RightHereKit"]
        ),
        // The setup window's model (`Apps/RightHere/SetupModel.swift`, linked in as it is), so that its states can be tested: the window itself cannot be.
        .target(
            name: "AppModel",
            dependencies: ["RightHereCore", "RightHereKit"]
        ),
        .executableTarget(
            name: "rh",
            dependencies: [
                "RightHereCore",
                "RightHereKit",
                "RightHereMCP",
                .product(name: "ArgumentParser", package: "swift-argument-parser")
            ]
        ),
        .testTarget(
            name: "RightHereCoreTests",
            dependencies: ["RightHereCore"]
        ),
        .testTarget(
            name: "RightHereKitTests",
            dependencies: ["RightHereKit", "RightHereCore"]
        ),
        // Starts the real `rh` binary; nothing here touches the real home directory or Finder.
        .testTarget(
            name: "RightHereCLITests",
            dependencies: ["rh", "RightHereKit", "RightHereCore"]
        ),
        // The window's model with a made-up Mac: a temporary home, fake facts, a scripted runner.
        .testTarget(
            name: "AppModelTests",
            dependencies: ["AppModel", "RightHereKit", "RightHereCore"]
        ),
        .testTarget(
            name: "RightHereMCPTests",
            dependencies: ["RightHereMCP", "RightHereKit", "RightHereCore"]
        )
    ]
)
