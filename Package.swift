// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "DocNest",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "DocNest", targets: ["DocNest"])
    ],
    targets: [
        .executableTarget(
            name: "DocNest",
            path: "DocNest"
        )
    ]
)