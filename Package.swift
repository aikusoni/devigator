// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "Devigator",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "Devigator", targets: ["Devigator"])
    ],
    targets: [
        .executableTarget(
            name: "Devigator",
            resources: [
                .copy("Resources/DefaultProfiles.json"),
                .copy("Resources/CapabilityCatalog.json")
            ]
        ),
        .testTarget(
            name: "DevigatorTests",
            dependencies: ["Devigator"]
        )
    ]
)
