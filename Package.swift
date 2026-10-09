// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TapAppLink",
  platforms: [
    .iOS(.v15),
    .macOS(.v12),
  ],
  products: [
    .library(name: "TapAppLink", targets: ["TapAppLink"]),
  ],
  targets: [
    .target(
      name: "TapAppLink",
      resources: [
        .process("PrivacyInfo.xcprivacy"),
      ]
    ),
    .testTarget(
      name: "TapAppLinkTests",
      dependencies: ["TapAppLink"]
    ),
  ]
)
