// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenPulse",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "TokenPulse", targets: ["TokenPulse"])
    ],
    targets: [
        .executableTarget(
            name: "TokenPulse",
            path: "Sources/TokenPulse",
            linkerSettings: [
                .linkedLibrary("sqlite3"),
                .linkedFramework("AppKit"),
                .linkedFramework("SwiftUI"),
                .linkedFramework("WebKit"),
                .linkedFramework("ServiceManagement")
            ]
        )
    ]
)
