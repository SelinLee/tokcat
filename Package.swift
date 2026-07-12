// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Tokcat",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .library(name: "TokcatKit", targets: ["TokcatKit"]),
        .executable(name: "TokcatApp", targets: ["TokcatApp"])
    ],
    targets: [
        .target(
            name: "TokcatKit",
            path: "Sources/TokcatKit",
            linkerSettings: [
                .linkedLibrary("sqlite3")
            ]
        ),
        .executableTarget(
            name: "TokcatApp",
            dependencies: ["TokcatKit"],
            path: "App"
        ),
        .testTarget(
            name: "TokcatKitTests",
            dependencies: ["TokcatKit"],
            path: "Tests/TokcatKitTests"
        )
    ]
)
