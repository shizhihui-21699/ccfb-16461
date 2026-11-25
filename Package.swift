// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PhishingResistantOTP",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "PhishingResistantOTP",
            targets: ["PhishingResistantOTP"]
        )
    ],
    targets: [
        .target(
            name: "PhishingResistantOTP"
        ),
        .testTarget(
            name: "PhishingResistantOTPTests",
            dependencies: ["PhishingResistantOTP"]
        )
    ]
)
