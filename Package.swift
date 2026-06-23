// swift-tools-version: 5.9
import PackageDescription

// SwiftPM build path — lets Glasnik build with just the Command Line Tools (no full
// Xcode). `./bundle.sh` wraps the resulting binary into Glasnik.app. The Xcode route
// via project.yml/XcodeGen still works too if you ever install Xcode.
//
// The global hotkey uses Carbon's RegisterEventHotKey directly (see GlobalHotKey.swift)
// rather than the KeyboardShortcuts package, which relies on the #Preview macro plugin
// that ships only with Xcode and so won't compile under CLT.
let package = Package(
    name: "Glasnik",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/argmax-oss-swift", from: "1.0.0"),
    ],
    targets: [
        .executableTarget(
            name: "Glasnik",
            dependencies: [
                .product(name: "WhisperKit", package: "argmax-oss-swift"),
            ],
            path: "Sources"
        )
    ]
)
