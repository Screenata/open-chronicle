// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Chronicle",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Chronicle",
            path: "Sources",
            linkerSettings: [
                .linkedFramework("ScreenCaptureKit"),
            ]
        ),
    ]
)
