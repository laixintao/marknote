// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Marknote",
    defaultLocalization: "en",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Marknote", targets: ["Marknote"])],
    targets: [
        .target(name: "MarknoteCore", resources: [.process("Resources")]),
        .executableTarget(name: "Marknote", dependencies: ["MarknoteCore"]),
        .executableTarget(name: "MarknoteCoreTests", dependencies: ["MarknoteCore"], path: "Tests/MarknoteCoreTests")
    ]
)
