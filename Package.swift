// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DeepUninstall",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "DeepUninstall", targets: ["DeepUninstall"]),
    ],
    targets: [
        // Pure logic: app discovery, leftover detection, removal. Fully unit-tested.
        .target(name: "DeepUninstallCore"),
        // SwiftUI front-end.
        .executableTarget(name: "DeepUninstall", dependencies: ["DeepUninstallCore"]),
        .testTarget(name: "DeepUninstallCoreTests", dependencies: ["DeepUninstallCore"]),
    ]
)
