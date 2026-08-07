// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "VivijureKit",
  platforms: [
    .iOS(.v16),
    .macOS(.v13),
  ],
  products: [
    .library(name: "VivijureKit", targets: ["VivijureKit"]),
  ],
  targets: [
    .target(name: "VivijureKit"),
    .testTarget(name: "VivijureKitTests", dependencies: ["VivijureKit"]),
  ]
)
