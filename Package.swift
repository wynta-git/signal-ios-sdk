// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SignalSDK",
    platforms: [.iOS(.v13)],
    products: [
        .library(
            name: "SignalSDK",
            targets: ["SignalSDK"]
        )
    ],
    targets: [
        .target(
            name: "SignalSDK",
            path: "Sources/SignalSDK"
        )
    ]
)
