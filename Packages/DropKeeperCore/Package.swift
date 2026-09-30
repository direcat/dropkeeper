// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DropKeeperCore",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "DropKeeperCore", targets: ["DropKeeperCore"])
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", exact: "7.11.1")
    ],
    targets: [
        .target(
            name: "DropKeeperCore",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .testTarget(
            name: "DropKeeperCoreTests",
            dependencies: ["DropKeeperCore"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
