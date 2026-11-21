// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "FileTray", platforms: [.macOS(.v13)],
    products: [.executable(name: "FileTray", targets: ["FileTray"])],
    targets: [.target(name: "TrayCore"), .executableTarget(name: "FileTray", dependencies: ["TrayCore"]),
              .testTarget(name: "TrayCoreTests", dependencies: ["TrayCore"])])
