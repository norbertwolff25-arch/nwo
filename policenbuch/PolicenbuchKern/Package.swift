// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "PolicenbuchKern",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "PolicenbuchKern", targets: ["PolicenbuchKern"])
    ],
    targets: [
        .target(name: "PolicenbuchKern"),
        .testTarget(
            name: "PolicenbuchKernTests",
            dependencies: ["PolicenbuchKern"],
            resources: [.copy("Testdaten")]
        )
    ]
)
