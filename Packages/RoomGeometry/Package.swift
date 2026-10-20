// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "RoomGeometry",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RoomGeometry", targets: ["RoomGeometry"]),
    ],
    targets: [
        .target(name: "RoomGeometry"),
        .testTarget(name: "RoomGeometryTests", dependencies: ["RoomGeometry"]),
    ]
)
