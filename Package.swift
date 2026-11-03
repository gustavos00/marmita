// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Marmita",
    platforms: [.macOS(.v14)],
    targets: [
        .target(name: "MarmitaCore"),
        .executableTarget(name: "Marmita", dependencies: ["MarmitaCore"]),
        .testTarget(name: "MarmitaCoreTests", dependencies: ["MarmitaCore"]),
    ],
    swiftLanguageModes: [.v5]
)
