// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "SuperSpock",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "SuperSpock", targets: ["SuperSpock"])],
    dependencies: [
        .package(url: "https://github.com/stasel/WebRTC", from: "109.0.1")
    ],
    targets: [
        .executableTarget(name: "SuperSpock", dependencies: [.product(name: "WebRTC", package: "WebRTC")]),
        .testTarget(name: "SuperSpockTests", dependencies: ["SuperSpock"])
    ]
)
