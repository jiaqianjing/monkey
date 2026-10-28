// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Monkey",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MonkeyInputMethod", targets: ["MonkeyInputMethod"]),
        .executable(name: "MonkeyBenchmark", targets: ["MonkeyBenchmark"]),
        .library(name: "MonkeyCore", targets: ["MonkeyCore"]),
        .library(name: "MonkeyPinyin", targets: ["MonkeyPinyin"])
    ],
    targets: [
        .target(name: "MonkeyCore"),
        .target(name: "CRimeBridge", publicHeadersPath: "include"),
        .target(name: "MonkeyPinyin", dependencies: ["CRimeBridge", "MonkeyCore"]),
        .target(name: "MonkeySettings", dependencies: ["MonkeyCore"]),
        .executableTarget(name: "MonkeyInputMethod", dependencies: ["MonkeyCore", "MonkeyPinyin", "MonkeySettings"]),
        .executableTarget(name: "MonkeyBenchmark", dependencies: ["MonkeyPinyin"]),
        .testTarget(name: "MonkeyCoreTests", dependencies: ["MonkeyCore"]),
        .testTarget(name: "MonkeyPinyinTests", dependencies: ["MonkeyPinyin"], exclude: ["Fixtures"])
    ],
    swiftLanguageVersions: [.v5]
)
