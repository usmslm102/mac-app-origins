// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "AppSourceScanner",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "AppSourceScanner", targets: ["AppSourceScanner"])
    ],
    targets: [
        .executableTarget(
            name: "AppSourceScanner",
            path: "Sources/AppSourceScanner"
        )
    ]
)
