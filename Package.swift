// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Notchy",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "HappyNotch", targets: ["Notchy"]),
    ],
    targets: [
        .executableTarget(
            name: "Notchy",
            path: "Sources/Notchy",
            linkerSettings: [.linkedFramework("Carbon"), .linkedFramework("WebKit")]
        ),
        .testTarget(
            name: "NotchyTests",
            dependencies: ["Notchy"],
            path: "Tests/NotchyTests"
        ),
    ]
)
