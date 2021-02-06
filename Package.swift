// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "Harvest-SwiftUI-Detector",
    platforms: [
        .macOS(.v10_15), .iOS(.v13), .tvOS(.v13), .watchOS(.v6)
    ],
    products: [
        .library(
            name: "Harvest-SwiftUI-VideoCapture",
            targets: ["Harvest-SwiftUI-VideoCapture"]),
        .library(
            name: "Harvest-SwiftUI-VideoDetector",
            targets: ["Harvest-SwiftUI-VideoDetector"]),
    ],
    dependencies: [
        .package(url: "https://github.com/inamiy/Harvest", from: "0.3.0"),
        .package(url: "https://github.com/inamiy/OrientationKit", from: "0.1.0"),
        .package(url: "https://github.com/SwiftyTesseract/SwiftyTesseract", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "Harvest-SwiftUI-VideoCapture",
            dependencies: [
                "Harvest",
                "OrientationKit",
                .product(name: "HarvestStore", package: "Harvest"),
                .product(name: "HarvestOptics", package: "Harvest")
            ]),
        .target(
            name: "Harvest-SwiftUI-VideoDetector",
            dependencies: [
                "SwiftyTesseract",
                "Harvest-SwiftUI-VideoCapture",
            ]),
    ]
)
