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
        .package(url: "https://github.com/dduan/TOMLDecoder", from: "0.4.5")
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
        .executableTarget(
            name: "rh",
            dependencies: ["RightHereCore", "RightHereKit"]
        ),
        .testTarget(
            name: "RightHereCoreTests",
            dependencies: ["RightHereCore"]
        )
    ]
)
