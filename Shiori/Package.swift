// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Shiori",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Shiori", targets: ["Shiori"])
    ],
    targets: [
        .executableTarget(
            name: "Shiori",
            path: "Sources"
        )
    ]
)
