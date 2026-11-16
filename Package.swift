// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "AntigravityHUD",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "TelemetryCore", targets: ["TelemetryCore"]),
        .library(name: "HUDShaders", targets: ["HUDShaders"]),
        .executable(name: "AntigravityHUDApp", targets: ["AntigravityHUDApp"])
    ],
    targets: [
        .target(
            name: "TelemetryCore",
            dependencies: [],
            path: "Sources/TelemetryCore",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .target(
            name: "HUDShaders",
            dependencies: [],
            path: "Sources/HUDShaders"
        ),
        .executableTarget(
            name: "AntigravityHUDApp",
            dependencies: ["TelemetryCore", "HUDShaders"],
            path: "Sources/AntigravityHUDApp"
        ),
        .testTarget(
            name: "TelemetryCoreTests",
            dependencies: ["TelemetryCore"],
            path: "Tests/TelemetryCoreTests"
        )
    ]
)
