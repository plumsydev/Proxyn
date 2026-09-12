// swift-tools-version: 6.0
import PackageDescription

// The platform-independent core (models, networking, formatting, demo backend)
// is also exposed as a Swift package so it can be unit-tested with `swift test`
// on macOS — no simulator, no Xcode project involved. The iOS app and the
// widget extension compile the same sources directly.
let package = Package(
    name: "ProxynCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "ProxynCore", targets: ["ProxynCore"])
    ],
    targets: [
        .target(
            name: "ProxynCore",
            path: "Shared",
            exclude: ["UI"]
        ),
        .testTarget(
            name: "ProxynCoreTests",
            dependencies: ["ProxynCore"],
            path: "Tests/ProxynCoreTests"
        )
    ],
    // Same language mode as the app targets (see project.yml).
    swiftLanguageModes: [.v5]
)
