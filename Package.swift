// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Orient",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "OrientCore", targets: ["OrientCore"]),
        .executable(name: "OrientApp", targets: ["OrientApp"])
    ],
    targets: [
        .target(
            name: "OrientCore",
            path: "Sources/OrientCore"
        ),
        .executableTarget(
            name: "OrientApp",
            dependencies: ["OrientCore"],
            path: "Sources/OrientApp"
        ),
        .testTarget(
            name: "OrientCoreTests",
            dependencies: ["OrientCore"],
            path: "Tests/OrientCoreTests"
        )
    ]
)

