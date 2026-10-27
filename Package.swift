// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ProxyUsage",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "ProxyUsage", targets: ["ProxyUsage"])],
    targets: [
        .executableTarget(name: "ProxyUsage"),
        .testTarget(name: "ProxyUsageTests", dependencies: ["ProxyUsage"])
    ]
)
