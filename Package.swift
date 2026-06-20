// swift-tools-version: 6.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "ProjectService",
    platforms: [.iOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "ProjectService",
            targets: ["ProjectService"]
        ),
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .binaryTarget(
            name: "XMPToolkit",
            path: "artifacts/XMPToolkit.xcframework"
        ),
        .target(
            name: "ProjectService",
            dependencies: ["XMPToolkit"]
        ),
        .testTarget(
            name: "ProjectServiceTests",
            dependencies: ["ProjectService", "XMPToolkit"]
        ),
    ],
    swiftLanguageModes: [.v6]
)
