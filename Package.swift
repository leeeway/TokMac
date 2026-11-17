// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TokMac",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TokMac", targets: ["TokMac"])
    ],
    targets: [
        .executableTarget(
            name: "TokMac",
            dependencies: ["TokMacCore"],
            path: "Sources/TokMac",
            resources: [.process("Scripts")]
        ),
        .target(name: "TokMacCore")
    ]
)
