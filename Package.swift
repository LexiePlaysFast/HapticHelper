// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "HapticHelper",
  dependencies: [
    .package(url: "https://github.com/apple/swift-nio",              from: "2.0.0"),
    .package(url: "https://github.com/apple/swift-async-algorithms", from: "1.0.0"),
  ],
  targets: [
    // Targets are the basic building blocks of a package, defining a module or a test suite.
    // Targets can depend on other targets in this package and products from dependencies.
    .executableTarget(
      name: "HapticHelper",
      dependencies: [
        .product(name: "NIOCore",         package: "swift-nio"             ),
        .product(name: "NIOPosix",        package: "swift-nio"             ),
        .product(name: "NIOHTTP1",        package: "swift-nio"             ),
        .product(name: "NIOWebSocket",    package: "swift-nio"             ),
        .product(name: "AsyncAlgorithms", package: "swift-async-algorithms"),
      ],
    ),
  ],
)
