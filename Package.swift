// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ThermalCam",
    platforms: [
        .macOS(.v15),
    ],
    products: [
        .executable(name: "ThermalCam", targets: ["ThermalCam"]),
        .library(name: "ThermalCore", targets: ["ThermalCore"]),
    ],
    targets: [
        .systemLibrary(
            name: "CLibusb",
            pkgConfig: "libusb-1.0",
            providers: [
                .brew(["libusb"]),
            ]
        ),
        .target(
            name: "ThermalCore",
            dependencies: ["CLibusb"]
        ),
        .executableTarget(
            name: "ThermalCam",
            dependencies: ["ThermalCore"],
            swiftSettings: [
                .swiftLanguageMode(.v5),
            ]
        ),
        .testTarget(
            name: "ThermalCoreTests",
            dependencies: ["ThermalCore"]
        ),
    ],
    swiftLanguageModes: [.v5]
)
