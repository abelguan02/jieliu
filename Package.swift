// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Jieliu",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Jieliu", targets: ["Jieliu"])],
    targets: [
        .target(name: "TrayCore"),
        .executableTarget(name: "Jieliu", dependencies: ["TrayCore"]),
        .executableTarget(name: "CoreChecks", dependencies: ["TrayCore"], path: "Tests/TrayCoreTests")
    ]
)
