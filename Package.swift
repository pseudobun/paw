// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "paw",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "paw", targets: ["paw"]),
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        // Pure logic (labels, geometry, fuzzy match, config, icon map): no AppKit, unit tested.
        .target(name: "PawCore"),
        // The app and its CLI: one binary.
        .executableTarget(
            name: "paw",
            dependencies: ["PawCore", .product(name: "Sparkle", package: "Sparkle")],
            swiftSettings: [.swiftLanguageMode(.v5)],
            linkerSettings: [
                // Sparkle.framework sits in paw.app/Contents/Frameworks.
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
                .linkedFramework("AppKit"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("Carbon"),
                .linkedFramework("QuartzCore"),
                .linkedFramework("ServiceManagement"),
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
        .testTarget(name: "PawCoreTests", dependencies: ["PawCore"]),
        .testTarget(name: "PawTests", dependencies: ["paw"]),
    ]
)
