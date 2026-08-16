// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AICodingStatusBar",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "AICodingStatusBar", targets: ["AICodingStatusBar"])],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3"),
        .executableTarget(name: "AICodingStatusBar", dependencies: ["CSQLite"]),
        .testTarget(name: "AICodingStatusBarTests", dependencies: ["AICodingStatusBar"])
    ]
)
