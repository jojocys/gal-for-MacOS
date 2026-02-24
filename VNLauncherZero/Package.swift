// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "VNLauncherZero",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "VNLauncherZero", targets: ["VNLauncherZero"])
    ],
    targets: [
        .executableTarget(
            name: "VNLauncherZero",
            path: "Sources"
        )
    ]
)

