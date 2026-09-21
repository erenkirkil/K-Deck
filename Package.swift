// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "KDeck",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "KDeck",
            targets: ["KDeck"]
        )
    ],
    dependencies: [],
    targets: [
        .executableTarget(
            name: "KDeck",
            dependencies: [],
            path: "Sources/KDeck",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "KDeckTests",
            dependencies: ["KDeck"],
            path: "Tests/KDeckTests"
        )
    ],
    swiftLanguageModes: [.v6]
)
