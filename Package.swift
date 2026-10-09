// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Jieliu",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Jieliu", targets: ["Jieliu"])],
    targets: [
        .target(name: "TrayCore", path: "apps/macos/Sources/TrayCore"),
        .executableTarget(name: "Jieliu", dependencies: ["TrayCore"], path: "apps/macos/Sources/Jieliu"),
        .executableTarget(name: "CoreChecks", dependencies: ["TrayCore"], path: "apps/macos/Tests/TrayCoreTests")
    ]
)
