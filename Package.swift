// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MacOSAudioForward",
  platforms: [.macOS("26.0")],
  products: [
    .executable(name: "MacOSAudioForward", targets: ["MacOSAudioForward"])
  ],
  targets: [
    .target(
      name: "AudioForwardBuffer",
      path: "Sources/AudioForwardBuffer",
      publicHeadersPath: "include"
    ),
    .executableTarget(
      name: "MacOSAudioForward",
      dependencies: ["AudioForwardBuffer"],
      path: "Sources/MacOSAudioForward",
      linkerSettings: [
        .linkedFramework("AppKit"),
        .linkedFramework("AVFoundation"),
        .linkedFramework("CoreAudio"),
        .linkedFramework("Network"),
        .linkedFramework("ServiceManagement"),
        .linkedFramework("SwiftUI"),
      ]
    ),
  ],
  swiftLanguageModes: [.v5]
)
