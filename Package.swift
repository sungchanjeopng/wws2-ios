// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WWS2iOS",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        .library(name: "WWS2Core", targets: ["WWS2Core"]),
        .library(name: "WWS2BLE", targets: ["WWS2BLE"])
    ],
    targets: [
        .target(
            name: "WWS2Core",
            path: "Sources/WWS2Core"
        ),
        .target(
            name: "WWS2BLE",
            dependencies: ["WWS2Core"],
            path: "Sources/WWS2BLE"
        ),
        .testTarget(
            name: "WWS2CoreTests",
            dependencies: ["WWS2Core"],
            path: "Tests/WWS2CoreTests"
        ),
        .testTarget(
            name: "WWS2BLETests",
            dependencies: ["WWS2BLE", "WWS2Core"],
            path: "Tests/WWS2BLETests"
        )
    ]
)
