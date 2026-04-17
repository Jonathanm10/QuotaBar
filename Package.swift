// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "QuotaBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "QuotaBarCore", targets: ["QuotaBarCore"]),
        .executable(name: "QuotaBar", targets: ["QuotaBarApp"]),
    ],
    targets: [
        .target(
            name: "QuotaBarCore"
        ),
        .executableTarget(
            name: "QuotaBarApp",
            dependencies: ["QuotaBarCore"],
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "QuotaBarCoreTests",
            dependencies: ["QuotaBarCore"]
        ),
    ]
)
