// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AIBackgroundRemovalRuntime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "droppy-ai-bg-runtime",
            targets: ["AIBackgroundRemovalRuntime"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", exact: "1.20.0")
    ],
    targets: [
        .executableTarget(
            name: "AIBackgroundRemovalRuntime",
            dependencies: [
                .product(name: "onnxruntime", package: "onnxruntime-swift-package-manager")
            ]
        )
    ]
)
