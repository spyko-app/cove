// swift-tools-version:5.10
import PackageDescription

let package = Package(
    name: "Cove",
    platforms: [.macOS("15.0")],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
    ],
    targets: [
        .executableTarget(
            name: "Cove",
            dependencies: [
                "SwiftTerm",
                .product(name: "Sparkle", package: "Sparkle"),
            ], path: "Sources/Cove",
            linkerSettings: [.linkedFramework("ScriptingBridge"), .unsafeFlags([
                "-Xlinker", "-sectcreate", "-Xlinker", "__TEXT",
                "-Xlinker", "__info_plist", "-Xlinker", "Resources/Info.plist",
            ])]),
        .testTarget(name: "CoveTests", dependencies: ["Cove"], path: "Tests/CoveTests"),
    ]
)
