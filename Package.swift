// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MacTubeConverter",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacTubeConverter", targets: ["MacTubeConverter"])
    ],
    targets: [
        .executableTarget(name: "MacTubeConverter"),
        .testTarget(name: "MacTubeConverterTests", dependencies: ["MacTubeConverter"])
    ]
)
