// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "VoiceTranscribeRuntime",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(
            name: "droppy-voice-runtime",
            targets: ["VoiceTranscribeRuntime"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "0.15.0")
    ],
    targets: [
        .executableTarget(
            name: "VoiceTranscribeRuntime",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ]
        )
    ]
)
