// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SuperSpock",
    platforms: [.macOS(.v15)],
    products: [.executable(name: "SuperSpock", targets: ["SuperSpock"])],
    targets: [
        .executableTarget(name: "SuperSpock"),
        .testTarget(name: "SuperSpockTests", dependencies: ["SuperSpock"])
    ]
)
