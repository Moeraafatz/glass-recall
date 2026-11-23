// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "GlassRecall",
    platforms: [
        .macOS(.v15)
    ],
    products: [
        .library(name: "GlassRecallCore", targets: ["GlassRecallCore"]),
        .library(name: "GlassRecallUI", targets: ["GlassRecallUI"]),
        .executable(name: "GlassRecall", targets: ["GlassRecall"]),
        .executable(name: "GlassRecallTools", targets: ["GlassRecallTools"])
    ],
    targets: [
        .target(
            name: "GlassRecallCore",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("ScreenCaptureKit"),
                .linkedFramework("Vision"),
                .linkedFramework("NaturalLanguage"),
                .linkedFramework("Accelerate"),
                .linkedFramework("ApplicationServices"),
                .linkedFramework("AppKit")
            ]
        ),
        .target(
            name: "GlassRecallUI",
            dependencies: ["GlassRecallCore"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit")
            ]
        ),
        .executableTarget(
            name: "GlassRecall",
            dependencies: ["GlassRecallCore", "GlassRecallUI"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("Carbon")
            ]
        ),
        .executableTarget(
            name: "GlassRecallTools",
            dependencies: ["GlassRecallCore", "GlassRecallUI"],
            linkerSettings: [
                .linkedFramework("SwiftUI"),
                .linkedFramework("AppKit"),
                .linkedFramework("CoreGraphics")
            ]
        ),
        .testTarget(
            name: "GlassRecallTests",
            dependencies: ["GlassRecallCore", "GlassRecallUI"]
        )
    ]
)
