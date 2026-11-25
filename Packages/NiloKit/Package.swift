// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "NiloKit",
    platforms: [.macOS(.v26), .iOS(.v26), .watchOS(.v26), .tvOS(.v26)],
    products: [
        .library(name: "NiloCore", targets: ["NiloCore"]),
        .library(name: "NiloUI", targets: ["NiloUI"]),
    ],
    targets: [
        // Models, tools, approvals, memory. No UI code here.
        .target(name: "NiloCore"),
        // Brand, the living mark, shared SwiftUI views.
        .target(name: "NiloUI", dependencies: ["NiloCore"]),
        .testTarget(name: "NiloCoreTests", dependencies: ["NiloCore"]),
    ]
)
