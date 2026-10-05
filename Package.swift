// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Phelsuma",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Phelsuma", targets: ["PhelsumaApp"])],
    targets: [
        .target(name: "PhelsumaCore"),
        .target(name: "PhelsumaUI", dependencies: ["PhelsumaCore"]),
        .executableTarget(name: "PhelsumaApp", dependencies: ["PhelsumaCore", "PhelsumaUI"]),
        .testTarget(name: "PhelsumaUITests", dependencies: ["PhelsumaUI", "PhelsumaCore"]),
        .testTarget(name: "PhelsumaCoreTests", dependencies: ["PhelsumaCore"])
    ]
)
