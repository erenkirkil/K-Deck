// swift-tools-version: 5.9
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
        )
    ]
)
