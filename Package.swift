// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "screen-to-codex",
  platforms: [.macOS("26.0")],
  products: [.executable(name: "screen-to-codex", targets: ["ScreenToCodex"])],
  targets: [
    .target(name: "ScreenToCodexCore"),
    .executableTarget(name: "ScreenToCodex", dependencies: ["ScreenToCodexCore"]),
    .testTarget(name: "ScreenToCodexCoreTests", dependencies: ["ScreenToCodexCore"]),
    .testTarget(name: "ScreenToCodexTests", dependencies: ["ScreenToCodex"]),
  ],
  swiftLanguageModes: [.v5]
)
