// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VibeBar",
    platforms: [
        .macOS(.v14),
    ],
    products: [
        .library(name: "VibeBarUI", targets: ["VibeBarUI"]),
        .executable(name: "VibeBar", targets: ["VibeBar"]),
    ],
    dependencies: [
        .package(url: "https://github.com/steipete/SweetCookieKit.git", from: "0.4.0"),
    ],
    targets: [
        .target(
            name: "VibeBarUI",
            dependencies: []),
        .executableTarget(
            name: "VibeBar",
            dependencies: [
                "VibeBarUI",
                .product(name: "SweetCookieKit", package: "SweetCookieKit"),
            ]),
    ])
