// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "paw",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "paw", targets: ["paw"]),
    ],
    targets: [
        // Pure logic (labels, geometry, fuzzy match, config, icon map): no AppKit, unit tested.
        .target(name: "PawCore"),
        // The app and its CLI: one binary.
        .executableTarget(
            name: "paw",
            dependencies: ["PawCore"],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .testTarget(name: "PawCoreTests", dependencies: ["PawCore"]),
    ]
)
