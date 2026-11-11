// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "hidpi-mirror",
    platforms: [.macOS(.v13)],
    targets: [
        // Thin Objective-C shim over the private CGVirtualDisplay API.
        .target(name: "CVirtualDisplay", linkerSettings: [.linkedFramework("CoreGraphics")]),
        // Pure logic (size parsing, target selection, reconcile decisions); unit-tested.
        .target(name: "HiDPICore"),
        .executableTarget(name: "hidpi-mirror", dependencies: ["CVirtualDisplay", "HiDPICore"]),
        .testTarget(name: "HiDPICoreTests", dependencies: ["HiDPICore"]),
    ]
)
