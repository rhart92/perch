// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Perch",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Perch", targets: ["Perch"])],
    targets: [
        .target(name: "PerchCore"),
        .executableTarget(name: "Perch", dependencies: ["PerchCore"]),
        .testTarget(name: "PerchCoreTests", dependencies: ["PerchCore"]),
    ],
    swiftLanguageModes: [.v5]
)
