// swift-tools-version: 6.0
import Foundation
import PackageDescription

var targets: [Target] = [
    .executableTarget(
        name: "MacsteamApp",
        dependencies: ["Sparkle"],
        path: "Sources/MacsteamApp"
    )
]

if FileManager.default.fileExists(atPath: "Tests/MacsteamAppTests") {
    targets.append(.testTarget(
        name: "MacsteamAppTests",
        dependencies: ["MacsteamApp"],
        path: "Tests/MacsteamAppTests"
    ))
}

let package = Package(
    name: "MacsteamApp",
    platforms: [
        .macOS(.v13)
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.9.6"),
    ],
    targets: targets
)
