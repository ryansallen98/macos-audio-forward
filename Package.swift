// swift-tools-version: 6.0

import PackageDescription

let package = Package(
  name: "MacOSAudioForward",
  platforms: [.macOS("26.0")],
  products: [
    .executable(name: "MacOSAudioForward", targets: ["MacOSAudioForward"])
  ],
  targets: [
    .executableTarget(
      name: "MacOSAudioForward",
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
