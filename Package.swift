// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "VibeBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .executable(
            name: "VibeBar",
            targets: ["VibeBar"]),
        .library(
            name: "VibeBarUI",
            targets: ["VibeBarUI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/SweetCookieKit.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "VibeBarUI"),
        .executableTarget(
            name: "VibeBar",
            dependencies: [
                "VibeBarUI",
                .product(name: "SweetCookieKit", package: "SweetCookieKit"),
            ]),
    ],
    swiftLanguageModes: [.v6]
)
