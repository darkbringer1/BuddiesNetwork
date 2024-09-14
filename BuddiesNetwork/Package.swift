// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

/// Credits to Can Yoldas  https://github.com/canyoldas0
let package = Package(
    name: "BuddiesNetwork",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "BuddiesNetwork",
            targets: ["BuddiesNetwork"]),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "BuddiesNetwork"),
        .testTarget(
            name: "BuddiesNetworkTests",
            dependencies: ["BuddiesNetwork"]),
    ]
)
