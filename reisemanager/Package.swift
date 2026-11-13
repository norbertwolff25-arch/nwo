// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "Reisemanager",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "ReisemanagerKern", targets: ["ReisemanagerKern"]),
        .executable(name: "reisemanager", targets: ["reisemanager"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.5.0"),
    ],
    targets: [
        .target(
            name: "ReisemanagerKern",
            dependencies: [.product(name: "GRDB", package: "GRDB.swift")]
        ),
        .executableTarget(name: "reisemanager", dependencies: ["ReisemanagerKern"]),
        .testTarget(
            name: "ReisemanagerKernTests",
            dependencies: ["ReisemanagerKern"]
        ),
    ]
)

// Die SwiftUI-Oberfläche gibt es nur auf dem Mac. Der Kern baut und testet auch unter Linux.
#if os(macOS)
package.products.append(.executable(name: "ReisemanagerApp", targets: ["ReisemanagerApp"]))
package.targets.append(.executableTarget(name: "ReisemanagerApp", dependencies: ["ReisemanagerKern"]))
#endif
