// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PantryCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "PantryCore", targets: ["PantryCore"])
    ],
    targets: [
        .target(name: "PantryCore"),
        .testTarget(name: "PantryCoreTests", dependencies: ["PantryCore"])
    ]
)
