// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppOrigins",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AppOrigins", targets: ["AppOrigins"])
    ],
    targets: [
        .executableTarget(
            name: "AppOrigins",
            path: "Sources/AppSourceScanner"
        )
    ]
)
