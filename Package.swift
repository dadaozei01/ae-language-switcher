// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "AELanguageSwitcher",
    platforms: [.macOS(.v13)],
    products: [
        .library(name: "AELanguageSwitcherCore", targets: ["AELanguageSwitcherCore"]),
        .executable(name: "AELanguageSwitcherApp", targets: ["AELanguageSwitcherApp"])
    ],
    targets: [
        .target(name: "AELanguageSwitcherCore"),
        .executableTarget(
            name: "AELanguageSwitcherApp",
            dependencies: ["AELanguageSwitcherCore"],
            exclude: ["Resources"]
        ),
        .testTarget(
            name: "AELanguageSwitcherCoreTests",
            dependencies: ["AELanguageSwitcherCore"]
        )
    ]
)
