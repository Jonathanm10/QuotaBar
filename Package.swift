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
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.0"),
    ],
    targets: [
        .target(
            name: "QuotaBarCore"
        ),
        .executableTarget(
            name: "QuotaBarApp",
            dependencies: [
                "QuotaBarCore",
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            resources: [.process("Resources")],
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"]),
            ]
        ),
        .testTarget(
            name: "QuotaBarCoreTests",
            dependencies: ["QuotaBarCore"]
        ),
    ]
)
