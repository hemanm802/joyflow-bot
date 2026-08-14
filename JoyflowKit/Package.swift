// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "JoyflowKit",
    platforms: [
        .macOS("26.0"),
        .iOS("18.0"),
    ],
    products: [
        .library(name: "JoyflowKit", targets: ["JoyflowKit"]),
    ],
    targets: [
        .target(
            name: "JoyflowKit",
            resources: [
                .copy("Resources/Plugins"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6),
                .enableUpcomingFeature("ExistentialAny"),
            ]
        ),
        .testTarget(
            name: "JoyflowKitTests",
            dependencies: ["JoyflowKit"],
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
    ]
)
