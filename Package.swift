// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CodexMeter",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CodexMeter", targets: ["CodexMeter"]),
        .executable(name: "CodexMeterWidget", targets: ["CodexMeterWidget"]),
        .executable(name: "codex-meter", targets: ["CodexMeterCLI"])
    ],
    targets: [
        .target(
            name: "CodexMeterShared",
            path: "Sources/CodexMeterShared"
        ),
        .executableTarget(
            name: "CodexMeter",
            dependencies: ["CodexMeterShared"],
            path: "Sources/CodexMeter"
        ),
        .executableTarget(
            name: "CodexMeterWidget",
            dependencies: ["CodexMeterShared"],
            path: "Sources/CodexMeterWidget",
            linkerSettings: [
                // Widget Extension targets are mainless: Xcode sets the
                // Foundation extension entry point instead of Swift's
                // executable entry point. SwiftPM has no first-class widget
                // target, so reproduce that linker setting here.
                .unsafeFlags(["-Xlinker", "-e", "-Xlinker", "_NSExtensionMain"])
            ]
        ),
        .executableTarget(
            name: "CodexMeterCLI",
            dependencies: ["CodexMeterShared"],
            path: "Sources/CodexMeterCLI"
        ),
        .testTarget(
            name: "CodexMeterTests",
            dependencies: ["CodexMeter"],
            path: "Tests/CodexMeterTests"
        )
    ]
)
